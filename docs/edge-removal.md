# Edge removal

- **Author:** AveYo
- **Source:** <https://github.com/AveYo/fox>, file `Edge_Removal.bat`
- **License:** the repository has no license file. UDP does not redistribute the script: it downloads it from the official repository each time it runs.
- **Pinned version:** commit `2be2a9052b02a6d99e84871d05f2d301762176ff` (2023-09-14, the latest change to that file when UDP was written), SHA256 `d4be8ed46ba80331a835aeef27064c79c0940206edba16da1da835351a06b107`. Both are in `config/tools.json`.
- **Default:** off. Tick it on the Edge removal page.

## Why not Microsoft's uninstaller?

Microsoft lets you uninstall Edge normally only in the **European Economic Area (EEA)**, as part of complying with the EU Digital Markets Act. In Switzerland and every other non-EEA country, the uninstall option does not work. The same limit applies to Win11Debloat's `-ForceRemoveEdge`, which UDP therefore never uses. AveYo's script works in every region.

## WebView2 is always kept

WebView2 is a separate copy of the Edge engine that other apps use to display web content (Teams, Outlook, Widgets, game launchers, many installers). Removing it breaks those apps.

AveYo's script removes WebView2 by default (`$also_remove_webview = 1`). UDP always sets it to `0`. Afterwards UDP checks that Edge is gone **and** WebView2 is still present, and marks the step as failed otherwise.

## How UDP runs the script

The `.bat` file is a batch/PowerShell hybrid:
- Its options are variables near the top of the embedded PowerShell code:
  - `$also_remove_webview`
  - `$also_remove_widgets`
  - `$also_remove_xsocial`
- There are no command-line options.
- Its launcher stores the code in the registry and re-opens it in a **new elevated PowerShell window started with `-NoExit`**. That window never closes by itself, so UDP could not wait for it.

So UDP:
1. Downloads the pinned file and checks its SHA256. A mismatch skips the step.
2. Takes the PowerShell code embedded between the launcher lines. It applies the same `$@` / `@$` marker swap that the launcher does.
3. Sets the three option lines. Each must be found exactly once, otherwise nothing runs:
   - `$also_remove_webview = 0`: always.
   - `$also_remove_widgets = 0` or `1`: your choice, default `0`. Win11Debloat already turns widgets off; this removes the Web Experience Pack itself.
   - `$also_remove_xsocial = 0` or `1`: your choice, default `0`. It removes Gaming Services, which the Xbox app and PC Game Pass need to install and run games.
4. Writes the result to `%TEMP%\UDP\work\edge\Edge_Removal.ps1` and logs the three option lines it used.
5. Runs it with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...` with no window, streams its output into the log, and waits for it to finish.
6. Makes sure Explorer is running again (the script restarts it).
7. Waits for Edge's own uninstaller to finish. It keeps running in the background after the script ends, so UDP waits up to 5 minutes until both Edge's entry in *Settings > Apps* and `msedge.exe` are gone.
8. Checks the result: the step succeeds when Edge is gone and WebView2 is still present. Otherwise the step fails and the log says exactly what is left.

## Never without a browser

- **Order:** this step runs after the browser step.
- **In the wizard:** if no other browser is installed and the browser step is off, the Edge page shows a warning and requires explicit confirmation.
- **During the run:** UDP checks again. If no other browser is found, it asks before removing Edge.

## Things to know

- **Edge may come back** after a major Windows feature update. Run UDP again: the step is skipped automatically when Edge is not installed.
- **Some system links** (search results, widgets, help links) are hard-wired to `microsoft-edge:`. The script installs AveYo's *OpenWebSearch* redirect so they open in your default browser, but a few may still try to open Edge.
- **Antivirus:** the script changes protected parts of Windows, so some security products may flag it. If it is blocked, the step is marked as failed and the run continues.

## How to undo

- Reinstall Edge from <https://www.microsoft.com/edge>.
- Or use the System Restore point UDP created at the start.
