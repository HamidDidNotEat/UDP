# Contributing to Ultimate Debloat Pack

Thanks for helping. Bug reports, tested fixes and documentation improvements are all welcome.

## Reporting a bug

[Open a bug report](https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/issues/new?template=bug_report.yml) and attach the UDP log. UDP writes one log file per run in `C:\ProgramData\UDP\logs` (`UDP_<date>_<time>.log`); Win11Debloat's own log is in the `Win11Debloat` subfolder.

For security problems, do **not** open a public issue: see [SECURITY.md](SECURITY.md).

## Ground rules

These rules are what makes UDP trustworthy. Pull requests that break them will not be merged.

1. **Official sources only.** Never add a third-party binary or script to the repository. Every tool is downloaded at run time from its official source.
2. **Every source lives in [`config/tools.json`](config/tools.json)**: URL, winget ID, expected signer, integrity method, license and homepage. Code reads it from there; no URL is hard-coded elsewhere.
3. **Verify before running.** Signed programs must pass `Test-UdpSignature` with the expected publisher. Unsigned files need a published checksum (release `SHA256SUMS`, GitHub asset digest or a pinned SHA256), and the exception is documented in `tools.json`.
4. **Never invent IDs, flags or file formats.** Check every winget ID, extension ID, command-line switch and config format against the tool's official documentation or source.
5. **No obfuscation.** Readable, commented code that anyone can audit. Avoid patterns that antivirus products flag (encoded commands, download-and-execute in memory).
6. **UDP never removes something on its own** when the tool is meant to be interactive (Bulk Crap Uninstaller, Autoruns).

## Development setup

- Windows 10 or 11 with the built-in **Windows PowerShell 5.1**. UDP must not require PowerShell 7 or any external module.
- A virtual machine with snapshots for real runs (Hyper-V is included in Windows Pro). Never test changes on your main PC.

Run the self-tests before every commit. They change nothing on the system:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\Test-UDP.ps1 -Online
```

| Switch | What it adds |
|--------|--------------|
| *(none)* | Syntax of every script, ASCII encoding, `tools.json`, helpers, every XAML page |
| `-Online` | Downloads the pinned Edge script and the latest Win11Debloat release and checks that UDP still understands them |
| `-DryRunSteps` | Runs every step in dry-run mode without the window (needs an elevated PowerShell) |

The same tests run on every push and pull request ([Tests workflow](.github/workflows/tests.yml)).

## Coding conventions

- **Windows PowerShell 5.1 compatible:** no ternary `? :`, no `??`, no `ForEach-Object -Parallel`, and `ConvertFrom-Json` has no `-AsHashtable`.
- **ASCII only** in `.ps1`, `.bat`, `.xaml`, `.json` and `.yml` files. Windows PowerShell 5.1 reads files without a byte order mark as ANSI, so any other character can break a script. The tests check this.
- **CRLF line endings** (enforced by `.gitattributes` and `.editorconfig`); `cmd.exe` needs them for `.bat` files.
- **Function names** start with a verb and `Udp`, for example `Get-UdpToolConfig` or `Invoke-UdpEdgeRemoval`.
- **Comments** explain *why*, not *what*. Match the style of the surrounding code.
- **Steps** live in `src/Steps/`, one file per tool, registered in `00-Catalog.ps1`. Each step provides `Test-...Available`, `Get-...Plan` and `Invoke-...`, and returns a `New-UdpStepResult`.
- **The UI thread** only talks to the background runner through `$Context.Sync` (see `src/Core/Runner.ps1`).

## Updating a tool source

1. Edit the tool's entry in `config/tools.json` (URL, winget ID, expected signer, or `url` + `commit` + `sha256` together for the Edge removal script).
2. Run the tests with `-Online`.
3. Test a real run in a VM.
4. Mention the change in `CHANGELOG.md` under *Unreleased*.

## Pull requests

- Keep each pull request focused on one change.
- Describe what you changed, why, and how you tested it (dry run, VM, which Windows build).
- Update the documentation (`README.md`, `docs/`) and `CHANGELOG.md` when behaviour changes.

## Releases (maintainers)

1. Set `project.version` in `config/tools.json`.
2. Move the *Unreleased* notes in `CHANGELOG.md` to a new version section and update the links at the bottom.
3. Commit, then tag and push: `git tag v0.1.1` and `git push origin main v0.1.1`.

The [Release workflow](.github/workflows/release.yml) checks that the tag matches `project.version`, builds `UDP.zip` and `SHA256SUMS`, and publishes the release with the notes from `CHANGELOG.md`. The one-liner then installs it.
