# Bulk Crap Uninstaller (BCU)

- **Author:** Marcin Szeniak (Klocman)
- **Source:** <https://github.com/BCUninstaller/Bulk-Crap-Uninstaller> (the repository moved there from `Klocman/Bulk-Crap-Uninstaller`), website <https://www.bcuninstaller.com/>, Apache-2.0 license
- **winget ID:** `Klocman.BulkCrapUninstaller`

## What it does

BCU lists every classic desktop program on the PC (OEM utilities, trial antivirus, old software). You can uninstall several at once, and BCU then finds the leftovers: registry keys, folders and shortcuts. It complements Win11Debloat, which handles the built-in Store apps.

**UDP never uninstalls anything by itself and ships no uninstall list.** BCU is interactive only: UDP shows a guide, opens BCU, and continues when you close it.

## Modes in UDP

**Run once (default).** UDP downloads the portable build (`BCUninstaller_<version>_portable.7z`) from the latest GitHub release, uses it, and deletes it with the temporary folder at the end.
- The archive is extracted with Windows' built-in `tar.exe`. Windows 11's `tar.exe` includes the LZMA library needed for `.7z`.
- On Windows 10, the older `tar.exe` may not have it. Then UDP installs BCU with winget for this run and uninstalls it at the end.

**Keep it installed** installs BCU with winget, and it stays installed.

## Integrity: a documented exception

BCU's binaries are **not Authenticode-signed** (checked on v6.3), so UDP cannot verify a publisher signature. Instead:
- **Portable:** UDP checks the SHA256 digest that GitHub publishes for the release file (the `digest` field of the release asset in the GitHub API). A mismatch skips the step.
- **Installed:** winget checks the installer hash from its manifest.

This exception is recorded in the `integrity.notes` of the `bcu` entry in `config/tools.json`.

## How to use it (shown again before BCU opens)

1. Tick the programs you want to remove and click **Uninstall**.
2. When BCU offers to look for leftovers, let it scan. BCU rates every leftover:
   - **Very good:** remove these.
   - **Good:** check them yourself before removing.
   - **Questionable** and **Bad:** leave them alone.
3. Keep **Show system components** and **Show protected items** switched off in the filter options on the left. They are off by default and hide entries that should not be removed.
4. You do not need BCU's startup manager: startup entries are reviewed later in Autoruns.

## Do NOT uninstall here

- GPU, chipset, audio or network drivers
- Microsoft Visual C++ Redistributables, .NET and DirectX runtimes
- Microsoft Edge WebView2 Runtime (many apps need it)
- Microsoft Edge itself (UDP removes it in a later step and keeps WebView2)
- Game anti-cheat services (Easy Anti-Cheat, BattlEye, Riot Vanguard, ...), or games stop launching

## Why it runs third

- **After Win11Debloat:** the program list is already shorter.
- **Before the new browser is installed:** the browser cannot be removed by mistake.
- **Before Autoruns:** Autoruns then shows only the startup entries that are left.

## How to undo

Uninstalls cannot be undone by UDP. Reinstall the program, or use the System Restore point UDP created at the start.
