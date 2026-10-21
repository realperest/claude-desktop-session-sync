# Claude Desktop Session Sync

**Keep one Code-tab session list across all your Claude accounts in the Claude desktop app on Windows.**

[Türkçe](README.tr.md) · [Technical findings](docs/FINDINGS.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

> Unofficial. Not affiliated with or endorsed by Anthropic. This tool relies on how the Claude desktop app stores its files today, which is not a published interface. An app update can break it. Read the [disclaimer](#disclaimer) before you use it.

## The problem

If you use more than one Claude account in the desktop app (for example a personal and a work account, or two accounts to spread usage limits), switching accounts makes your **Code** tab sessions disappear from the sidebar. They are not deleted: the conversations are still on disk in `~/.claude/projects`. But the app keeps a separate sidebar list for every account and organization:

```
<app data>\claude-code-sessions\<account id>\<organization id>\local_<session id>.json
```

When you sign in to the other account, the app reads the other folder, and your sessions are gone from view. Anthropic has no built-in fix for accounts with different email addresses yet. See [anthropics/claude-code#74662](https://github.com/anthropics/claude-code/issues/74662) and [#48511](https://github.com/anthropics/claude-code/issues/48511).

## What this does

A PowerShell script keeps every account and organization folder in sync, so the sidebar shows the same sessions whichever account you sign in to.

- **Two-way sync by copying.** The newest valid version of every session record is copied to every other folder. Last-write times are kept, so nothing bounces back and forth. An account can use more than one organization folder; all of them are synced.
- **Background watcher.** A hidden watcher syncs every 15 seconds (every 2 seconds while the app is closed). When you switch accounts, the other account's list is already up to date, so you do not need to restart the app.
- **Deleted sessions stay deleted.** When you delete a session, the app writes a `deleted_<id>` marker. The script matches it against every id of a record (`cliSessionId`, `unarchivedCliSessionId`, `priorCliSessionIds`, and the id in the file name) and moves leftover copies to a backup folder instead of deleting them.
- **Corrupt records never spread.** A half-written or corrupt record is never copied and never overwrites a good copy.
- **Missing-entry repair.** If a conversation exists on disk but has no sidebar entry (this happens when the app moves its data folder, or when it cannot save), the script rebuilds the entry from the transcript.
- **Worktree repair.** It fixes worktree sessions whose entry was rebuilt and that fail with *"Something went wrong"* / `branch is checked out somewhere else` (see [findings](docs/FINDINGS.md#worktree-lease)).
- **Shared settings.** Saved environment presets and MCP tool toggles are merged across accounts, but only while the app is closed.
- **Safe by design.** It never deletes files, backs up before every change, writes atomically, and never touches account credentials, passwords, or tokens.

### Why not just link the folders?

Earlier versions linked the account folders with NTFS junctions. **Do not do that.** Current app versions refuse to write into a linked folder (`Refusing non-directory at private dir path (symlink/file plant)` in the app log). The app can still read through the link, so everything looks fine, but new sessions and changes are never saved and are lost at the next account switch or restart. This tool converts any junction it finds back into a real folder. Details in [findings](docs/FINDINGS.md#junctions).

## Requirements

- Windows 10 or 11
- The Claude desktop app, either the Microsoft Store version or the direct download. It has been tested with the Store (MSIX) version.
- Windows PowerShell 5.1 (included with Windows). No admin rights are needed.
- Git, or download the repository as a ZIP file.

## Install

1. **Get the files.**

   ```bash
   git clone https://github.com/realperest/claude-desktop-session-sync.git
   ```

   Or click **Code > Download ZIP** on GitHub and extract it.

2. **Do a dry run.** Nothing is changed; the installer only lists what it would do.

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-desktop-session-sync\kur.ps1 -Deneme
   ```

3. **Install.**

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-desktop-session-sync\kur.ps1
   ```

4. **Fully quit and reopen the Claude app.** Right-click the Claude icon in the system tray and choose **Quit**. Closing the window is not enough; the app keeps running in the background. Check Task Manager to confirm that no Claude process is left.

5. **Sign in to each of your accounts at least once on this computer.** An account's folder is created on its first sign-in, and the watcher syncs it within seconds.

### What the installer does

1. Finds your user folder and the Claude data folder.
2. Backs up `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, and any older copy of the script to `%USERPROFILE%\Claude-hesap-esitleme\yedek\kurulum_<time>\`.
3. Copies the sync script to `%USERPROFILE%\Claude-hesap-esitleme\`.
4. Adds a `SessionStart` hook to `~/.claude/settings.json`, so the script runs whenever a Claude Code session starts. Your other settings and hooks are left untouched, and the hook is never added twice.
5. Adds a short section to `~/.claude/CLAUDE.md` that explains the setup to Claude, using this computer's paths. If the section exists, it is updated.
6. Registers a Windows scheduled task that runs the script at logon, before the app starts.
7. Runs the sync once as a dry run and once for real. The real run also starts the background watcher.

If any step fails, everything changed up to that point is restored from the backup. Every step is logged to the screen and to `%USERPROFILE%\Claude-hesap-esitleme\kurulum.log`.

### Installer options

| Option | What it does |
|---|---|
| `-Deneme` | Dry run: shows what would happen and changes nothing. |
| `-Kaldir` | Uninstall: removes the hook, the `CLAUDE.md` section, and the scheduled task, and stops the watcher. The script, logs, and backups stay in place. |
| `-GorevKurma` | Does not install or remove the scheduled task. |
| `-EsitlemeAtla` | Does not run the sync after installing. |
| `-KullaniciKlasoru <path>` | Installs into another user folder (for testing). |

Uninstalling does not touch your session records. Each account folder keeps what was synced up to that point; later changes just stop being shared.

## Update

```bash
git -C .\claude-desktop-session-sync pull
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-desktop-session-sync\kur.ps1
```

The installer can be run again at any time. It leaves unchanged files alone, never duplicates the hook, and refreshes the `CLAUDE.md` section. A running watcher notices the new script and restarts itself.

## Everyday use

- **Switching accounts:** let any running reply finish, sign out, sign in to the other account, and check the sidebar. No restart is needed.
- **If something is missing after a switch:** fully quit the app from the tray and reopen it.
- **Script commands** (run from `%USERPROFILE%\Claude-hesap-esitleme\`):

| Command | What it does |
|---|---|
| `hesap-oturum-esitle.ps1 -KuruCalisma` | Dry run: logs what would change, changes nothing. |
| `hesap-oturum-esitle.ps1` | One full sync and repair run, then starts the watcher if it is not running. |
| `hesap-oturum-esitle.ps1 -ZorlaDuzelt` | Runs the worktree fixes even while the app is open. They take effect after a full restart. |
| `hesap-oturum-esitle.ps1 -GorevKur` | Installs or refreshes the logon task. |

## Troubleshooting

Start with a dry run and read the log:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Claude-hesap-esitleme\hesap-oturum-esitle.ps1" -KuruCalisma
```

The log is `%USERPROFILE%\Claude-hesap-esitleme\esitleme.log`. When it passes 5 MB, it is renamed to `esitleme_<time>.log` and a new one starts. Backups are in `%USERPROFILE%\Claude-hesap-esitleme\yedek\`.

| Symptom | What to check |
|---|---|
| New sessions vanish after a switch or restart | Search the app log `%LOCALAPPDATA%\Claude\logs\main.log` for `Failed to save session`. If you see `symlink/file plant`, a folder is still a junction; run the script once. |
| Every message in one session ends with "Something went wrong" | Search the app log for `not recreating its worktree`. Quit the app from the tray, wait 30 seconds, and reopen it; the watcher repairs the entry while the app is closed. |
| A project appears twice in the sidebar | There is probably a manually created sidebar group with the same name as the project. Delete that group in the app; its sessions are not deleted. |
| Orange "needs input" dots come back after every account switch | This is app behavior, not caused by this tool. See [findings](docs/FINDINGS.md#orange-dots). |
| A fix does not seem to apply | Make sure the app really restarted: a new `Loaded N persisted sessions` line must appear in the app log. |

To check that the watcher is running:

```bash
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object CommandLine -match '-Izle' | Select-Object ProcessId,CreationDate"
```

When you open an issue, include the last 30 lines of `esitleme.log`, your Claude app version, and whether you use the Store or the direct-download app. Do not paste tokens or the contents of `config.json`.

## Using two accounts without switching

The desktop app's sign-in is separate from the sign-in of Claude Code in the terminal and in the VS Code or Cursor extension. According to the [official docs](https://code.claude.com/docs/en/vs-code), the extension and the CLI share the same conversation history, which is stored locally and is not tied to an account. So you can keep the desktop app signed in to one account and the extension or terminal signed in to the other, and never switch. The trade-off is that each side keeps its own session list.

## The future: built-in multi-account

The desktop app already contains a multi-account feature behind a server-side flag. It also has an organization policy, `disableMultiAccount` ("Single account only"). Anthropic appears to be rolling the feature out gradually. Do not try to force it on. When you see an option to add another account in the account menu, check whether you still need this tool.

## What is not shared

- Sidebar custom groups and pins
- The "Mark as completed" state of sidebar dots
- claude.ai connectors, skills, and plugins
- Cloud sessions and background agent sessions
- Anything on another computer. This tool works per computer, because transcripts and worktrees live on each computer's own disk.

## Files

| File | Purpose |
|---|---|
| `hesap-oturum-esitle.ps1` | The sync script. The hook, the logon task, and the watcher (`-Izle`) all run this file. |
| `kur.ps1` | Installer and uninstaller. |
| `sablon/claude-md-bolum.md` | Template of the section written into `~/.claude/CLAUDE.md`. |
| `tests/Test-Sync.ps1` | End-to-end test on a fake data folder. It never touches your real Claude data. |
| `docs/FINDINGS.md` | How the desktop app stores sessions, and what we learned while building this. |
| `docs/MACOS-KILAVUZ.md` | Turkish handoff guide for porting the tool to macOS: the full history of the problems and fixes, the final design, and the porting plan. macOS support is planned but not available yet. |

The scripts' internal names, log messages, and comments are in Turkish, because the project started as a personal tool. Contributions that translate them are welcome.

## Disclaimer

This is an unofficial tool. It is not affiliated with, endorsed by, or supported by Anthropic. It reads and writes files in the Claude desktop app's data folder whose format is undocumented and may change without notice. The tool makes backups before every change and never deletes files, but you use it at your own risk. Keep your own backups of `%LOCALAPPDATA%\Claude-Data` (or `%APPDATA%\Claude`) and `%USERPROFILE%\.claude\projects`.

## License

[MIT](LICENSE)
