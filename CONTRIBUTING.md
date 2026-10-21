# Contributing

Thanks for helping. This tool works with undocumented internals of the Claude desktop app, so real-world reports are the most valuable contribution.

## Reporting a problem

Open an issue with the **Bug report** form and include:

- your Claude desktop app version and whether it is the Microsoft Store or the direct-download build,
- your Windows version,
- the last 30 lines of `%USERPROFILE%\Claude-hesap-esitleme\esitleme.log`,
- any matching lines from `%LOCALAPPDATA%\Claude\logs\main.log`, especially `Failed to save session`, `not recreating its worktree`, and `Loaded N persisted sessions`.

Never paste tokens, cookies, or the contents of `config.json`. Replace your email address and account ids with placeholders if you prefer.

## Changing the code

- Windows PowerShell 5.1 is the target. Do not use PowerShell 7-only syntax.
- Save `.ps1` files as UTF-8 **with** BOM. Without a BOM, Windows PowerShell 5.1 misreads non-ASCII characters.
- The tool must never delete user data. Move things to the backup folder instead, and back up before every change.
- Write files atomically: write to a temp file, then replace the target.
- Do not write to the app's Local Storage (LevelDB), and do not link folders with junctions or symlinks. See [docs/FINDINGS.md](docs/FINDINGS.md).
- Run the test before opening a pull request:

  ```bash
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Sync.ps1
  ```

  It builds a fake app data folder in your temp directory and never touches your real Claude data. The same test runs on GitHub Actions for every push and pull request.

Internal names, log messages, and comments are in Turkish because the project started as a personal tool. Pull requests that add English translations are welcome.
