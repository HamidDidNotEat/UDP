# Win11Debloat

- **Author:** Raphire
- **Source:** <https://github.com/Raphire/Win11Debloat> (MIT license)
- **How UDP gets it:** the latest GitHub release (`Win11Debloat.zip`), checked against the `SHA256SUMS` file published with the same release. There is no winget package. The script is not Authenticode-signed, so the published checksum is the integrity check.
- **Runs:** silently, with no window. Its output is streamed into UDP's log panel, and its own transcript goes to `%ProgramData%\UDP\logs\Win11Debloat`.

## What it does

Win11Debloat removes preinstalled Store (Appx) apps and applies registry tweaks for privacy and usability: telemetry, ads, suggestions, Bing in search, Copilot, Recall and more. It works on Windows 11 and Windows 10; options that only exist on one version are skipped automatically.

## Modes in UDP

**Recommended defaults** runs Win11Debloat with `-RunDefaults -Silent`. This is Win11Debloat's own default preset (its `Config/DefaultSettings.json`). It:
- removes its default app selection
- turns off telemetry and targeted ads, tips and suggestions, lock screen tips and Edge ads
- turns off Bing web results and Store suggestions in search
- turns off Copilot, Recall, Click to Do and the AI service auto-start
- turns off widgets and hides the Chat icon
- shows file extensions and hides 3D Objects
- turns off network access during Modern Standby

**Custom** shows a curated list of Win11Debloat's main options as checkboxes and passes the matching switches (for example `-DisableTelemetry -DisableBing -RemoveApps -Silent`). The list lives in `config/tools.json` under `win11debloat.customOptions`, with the Windows build each option needs.

Before running, UDP reads the parameter list of the downloaded `Win11Debloat.ps1`. Any switch that no longer exists in a newer Win11Debloat release is dropped with a warning instead of breaking the run.

## Switches UDP never passes

- `-ForceRemoveEdge`: Win11Debloat's Edge removal relies on Microsoft's uninstaller, which only works in the EEA. UDP's own Edge removal step handles Edge instead.
- `-CreateRestorePoint`: UDP has already created one. The default preset still asks for a restore point, but Win11Debloat skips it when one was made in the last 24 hours.
- `-CLI`, `-Sysprep`, `-User`, `-Config`, `-RunSavedSettings`: not used by UDP.

Win11Debloat has no reboot prompt. It restarts Explorer at the end, so the screen may flicker. UDP makes sure Explorer is running again afterwards.

## Dry run

In dry-run mode UDP passes `-WhatIf`, Win11Debloat's own preview mode. It prints what it would change and changes nothing.

## Risks

- A removed app is gone until you reinstall it from the Microsoft Store.
- Some tweaks hide features you might use (widgets, Copilot, Start recommendations).

## How to undo

- Win11Debloat saves a registry backup before it changes anything. Run Win11Debloat again and use its restore-backup option.
- Reinstall removed apps from the Microsoft Store.
- Or use the System Restore point UDP created at the start.
