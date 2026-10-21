# Changelog

## 1.0.0 - 2026-10-21

First public release.

- Two-way sync of every account and organization folder by copying. The newest valid record wins, and last-write times are kept.
- Background watcher: syncs every 15 seconds (every 2 seconds while the app is closed), runs repair and settings sync every 10 minutes, and restarts itself when the script changes. It logs only runs that add a file or set one aside.
- Converts NTFS junctions left by earlier versions back into real folders, because current app versions refuse to save into them.
- Deletion markers are matched against every id of a record (`cliSessionId`, `unarchivedCliSessionId`, `priorCliSessionIds`, file name). Leftover copies are moved to a backup folder.
- Corrupt or half-written records are never copied and never overwrite a good copy.
- Rebuilds missing sidebar records from transcripts. Rebuilt worktree sessions reuse the worktree registry's lessee id and get a worktree anchor.
- Repairs worktree leases and anchors of broken worktree sessions while the app is closed, or with `-ZorlaDuzelt`.
- Merges saved environment presets and MCP tool toggles across accounts while the app is closed.
- Log rotation at 5 MB. The first run no longer fails when the script folder does not exist yet.
- Installer `kur.ps1` with dry run, uninstall, rollback on failure, a `SessionStart` hook, a logon task, and a `CLAUDE.md` section.
- End-to-end test `tests/Test-Sync.ps1`, run on GitHub Actions.
