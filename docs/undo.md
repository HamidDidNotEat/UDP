# How to undo UDP's changes

## Everything at once: System Restore

UDP creates a restore point named **"UDP (Ultimate Debloat Pack) <date> <time>"** before it changes anything. If System Protection was off on the system drive, UDP turns it on first.

1. Open Start, type **Create a restore point** and open it.
2. Click **System Restore...** and choose the UDP restore point.
3. Follow the steps. Windows restarts.

System Restore brings back system files, drivers, installed programs and registry settings. It does not touch your personal files.

If Windows does not start normally: boot into the recovery environment (hold Shift while clicking Restart) and choose *Troubleshoot > Advanced options > System Restore*.

## Tool by tool

| Tool | Undo |
|------|------|
| Win11Debloat | Run Win11Debloat again ([github.com/Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)) and restore the registry backup it made. Reinstall removed apps from the Microsoft Store. |
| O&O ShutUp10++ | Open ShutUp10++ and use *Actions > Undo all changes*. |
| Bulk Crap Uninstaller | Reinstall the programs you removed. UDP cannot undo uninstalls. |
| Browser | Uninstall it from *Settings > Apps*. |
| Browser extension policies | Welcome page > **Revert browser policies created by UDP**, or `UDP.ps1 -RevertBrowserPolicies`. Only the entries UDP added are removed (see [browser.md](browser.md)). |
| Edge | Reinstall from [microsoft.com/edge](https://www.microsoft.com/edge). |
| NVCleanstall / NVIDIA driver | Install the standard driver from [nvidia.com/drivers](https://www.nvidia.com/drivers). Uninstall NVCleanstall from *Settings > Apps*. |
| Autoruns | Open Autoruns again and tick the entries you unticked. |

## What UDP leaves on the PC

- `%ProgramData%\UDP\logs\`: one log file per run, plus Win11Debloat's transcript.
- `%ProgramData%\UDP\state.json`: the browser policies UDP created, so they can be reverted.
- Programs you chose to keep: the browser, BCU in "Keep it installed" mode, NVCleanstall.

Everything else (downloads, portable tools) lives in `%TEMP%\UDP` and is deleted at the end of the run. You can delete `%ProgramData%\UDP` at any time, but revert the browser policies first if you want UDP to remove them for you.
