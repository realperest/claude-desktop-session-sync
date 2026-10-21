# Technical findings

How the Claude desktop app (Windows, Microsoft Store build) stores Code-tab sessions, and what we learned while building this tool. Everything here comes from observing the app's files, its log, and its behavior, mostly on app version 3.1623 with Claude Code 2.1.304 (October 2026). None of it is a published interface, and any of it may change with an app update.

## Where things live

| What | Where |
|---|---|
| App data folder (Store build, current) | `%LOCALAPPDATA%\Claude-Data\claude_<publisher id>\` |
| App data folder (Store build, older) | `%LOCALAPPDATA%\Packages\Claude_<publisher id>\LocalCache\Roaming\Claude\`, which apps inside the package see as `%APPDATA%\Claude` |
| App data folder (direct download) | `%APPDATA%\Claude\` |
| Sidebar records | `<data>\claude-code-sessions\<account id>\<organization id>\local_<session id>.json` |
| Deletion markers | `<data>\claude-code-sessions\<account id>\<organization id>\deleted_<id>` |
| Worktree registry | `<data>\git-worktrees.json` |
| Conversation transcripts | `%USERPROFILE%\.claude\projects\<project>\<cli session id>.jsonl` (shared by all accounts) |
| App log | `%LOCALAPPDATA%\Claude\logs\main.log` |
| Renderer state (sidebar dots, panes) | `<data>\Local Storage\leveldb\` |

The app moved its data folder from the `Packages` location to `Claude-Data` by itself during an update. A marker file was left in the old location. Always resolve the real path; never write through the virtualized `%APPDATA%` path from outside the package.

## Sidebar records

- The sidebar is built from the `local_*.json` files in the folder for the current account **and organization**. One account can use more than one organization folder: we saw the same account load its list from two different organization folders on different starts. A sync tool must cover every folder, not just one per account.
- The active folder is visible in the app log as `Loaded N persisted sessions from <path>`.
- A record links to its transcript through `cliSessionId`. A record can also carry `unarchivedCliSessionId` and `priorCliSessionIds`, and the app treats all of them as ids of the same session. For sessions imported from the CLI, the file name itself is `local_<cli session id>.json`.
- The app writes a record only when the session's metadata changes (title, remote control, focus, and similar). It does not write on every message.
- The app reads the list once when it starts or when you sign in, and it keeps records in memory. A record changed on disk while the app is open may be overwritten by the app's in-memory copy. Changes that the app must notice need a full restart: tray icon, right-click, **Quit**. Closing the window does not quit the app.

## Junctions

Linking the account folders with NTFS junctions looks like the obvious fix, and earlier versions of this tool did that. Current app versions refuse to write into them:

```
Failed to save session local_...: Refusing non-directory at private dir path (symlink/file plant): ...\claude-code-sessions\<account>\<org>
```

The app can still read through the junction, so the sidebar looks complete. But no new session and no change is ever saved. Everything opened since the junction was created exists only in memory and is lost at the next account switch or restart. In our case, messages in the affected sessions also failed with "Couldn't send" / "Gönderilemedi". The only safe approach is to keep real folders and copy between them.

## Deletion markers

When you delete a session, the app removes its record and writes `deleted_<id>` in the active folder, with a timestamp as content. If another account's folder still has a copy of the record, a naive sync copies the deleted session back. A sync tool has to:

- read every marker in every folder,
- compare each marker against **all** ids of a record (`cliSessionId`, `unarchivedCliSessionId`, `priorCliSessionIds`, and the id in the file name), not only the file name or only `cliSessionId`,
- propagate the marker, and set leftover copies aside.

## Missing entries

A transcript can exist without any sidebar record. This happens when the app moves its data folder while sessions are open, or when it cannot save (see [Junctions](#junctions)). Such a session can be rebuilt from its transcript: the working folder, title (`custom-title` line), branch, model, and timestamps are all in the `.jsonl` file. Do not rebuild a transcript when:

- its first lines do not say `"entrypoint":"claude-desktop"`, because it is a CLI or SDK session;
- there is a `deleted_<id>` marker, or a `<id>.desktop-released.json` file next to the transcript, because the user deleted it;
- it was created in the last few minutes, because the app may still be writing its record;
- its id appears in a `Mapping internal session local_X to CLI session Y` log line for a record that still exists. In that case it is an old id of a live session.

## Worktree lease

Rebuilding the record of a **worktree** session is not enough. The app keeps a registry of worktrees in `<data>\git-worktrees.json`:

```json
{ "worktrees": { "<name>": { "path": "...", "leasedBy": "local_<session id>", "branch": "...", "anchors": [ ... ] } } }
```

The app treats a worktree as a session's own only when `leasedBy` equals that session's id. If a rebuilt record gets a new id, the registry still points to the old one. On every message, the app then tries to create the worktree again, Git refuses because the branch is already checked out there, and the session fails:

```
the session's branch is checked out in a folder that exists; not recreating its worktree
Failed to warm session local_...: Git is installed but isn't working: this session's branch is checked out somewhere else in this repository
```

In the UI, every message in that session ends with "Something went wrong" / "Bir şeyler ters gitti". The fixes are:

1. When rebuilding a record, reuse the registry's old lessee id as the new session id, if no record with that id exists.
2. For existing broken records, re-lease the worktree to the session that uses it, but only when the current lessee has no record in any folder.
3. Also give the record an anchor for the worktree itself in `gitAnchors` (`gitRoot`, `commonDir`, and `gitDir` from the `gitdir:` line in `<worktree>\.git`).

Do all of this only while the app is closed, because the app rewrites both files from memory. Then do a real restart.

## Orange dots

The orange sidebar dot means the session is waiting for you: "needs input", "failed", or, on the start screen, "Blocked ... Asked a question". Opening the session does not clear it; **Mark as completed** does.

- The dot appears when the session's last turn left the user something open. Most often the last "next step" box asked a question, or the turn ended without a box at all. A typed reply to a box question is fine, as long as the assistant then closes its turn with a new box.
- "Mark as completed" is stored in renderer Local Storage under `epitaxy-awaiting-ack-v1` as `{"state":{"ackedAt":{"local_<id>": <ms>}}}`. Read state is stored under `epitaxy-unread-v1`.
- **At every sign-out, the app deletes exactly these two keys.** Other Local Storage keys survive. That is why all your "completed" marks disappear after each account switch, and the dots come back. This happens without this tool; the tool does not touch Local Storage.
- The box state of a turn is stored in the session record (`turnWrapUp`), which is synced across accounts. Sessions whose last turn closed cleanly with a box keep no dot after a switch.

Practical advice: close each piece of work with a turn that ends in a box without an open question, or ask Claude to always close turns that way. Switching accounts without signing out would also keep the marks, but we have not verified whether the app clears them on an identity change as well.

## Shared settings

Two plain settings files in the data folder are kept per account: `ccd-session-presets.json` (`byAccount.<account>.presets`) and `mcp-user-tool-toggles.json` (`owners.<account>`). They can be merged, but only while the app is closed. While the app is open, it rewrites them from memory and drops any change.

## Built-in multi-account

The app contains a multi-account feature behind a server-side feature flag, and an organization policy `disableMultiAccount` titled "Single account only" (available since app version 1.46388.1, marked undocumented). It was not enabled for our accounts in October 2026. When it ships, it may make this tool unnecessary.

## Official partial features

- `claude --desktop --resume <session id>`, `/desktop`, and `/resume` inside the desktop app bring **CLI-started** sessions into the desktop app. They do not bring over sessions that were started in the desktop app under another account.
- The VS Code extension and the CLI share one local conversation history that is not tied to an account. See the [official docs](https://code.claude.com/docs/en/vs-code).
