# Order of operations

UDP always runs in this order. The order is fixed in `src/Steps/00-Catalog.ps1`, and `tests/Test-UDP.ps1` checks it.

| # | Step | Kind |
|---|------|------|
| 0 | Checks (admin, Windows build, PowerShell 5.1, internet, winget, GPU, installed browsers) | automatic, read-only |
| 1 | System Restore point | automatic |
| 2 | Win11Debloat | silent |
| 3 | O&O ShutUp10++ | interactive (or silent with your exported file) |
| 4 | Bulk Crap Uninstaller | interactive |
| 5 | Alternative browser + extensions | silent, then you set the default browser in Settings |
| 6 | Edge removal | silent |
| 7 | NVCleanstall | interactive, NVIDIA GPUs only |
| 8 | Autoruns | interactive |
| 9 | Results and one restart | you choose now or later |

## Why this order

- **Restore point first:** everything after it can be undone in one go.
- **Win11Debloat before BCU:** Win11Debloat removes the built-in Store apps, so BCU's list of programs is already shorter and easier to review.
- **ShutUp10++ early:** its privacy settings do not depend on which programs are installed. Applying them early means later installs (the browser, NVCleanstall) already run with telemetry restricted.
- **BCU before the new browser:** the browser you are about to install cannot appear in BCU's list, so it cannot be removed by mistake.
- **Browser before Edge removal:** you are never left without a browser. If the browser step fails or is off and no other browser is installed, UDP asks before removing Edge.
- **NVCleanstall near the end:** the driver installation can make the screen go black for a moment and may want a restart. With every other change already done, the single restart at the end covers it too.
- **Autoruns last:** every uninstall is done by then, so Autoruns shows only the startup entries that are really left.

## One window at a time

Each step must finish before the next one starts:
- **Silent tools** run with no visible window. Their output is streamed into UDP's log panel.
- **Interactive tools** (ShutUp10++ in GUI mode, BCU, NVCleanstall, Autoruns) get a short explanation screen first. UDP then opens the tool and waits until it is closed, including any second copy the tool starts, before it continues.

## When a step fails

The step is marked as failed with the reason, and the details go to the log. UDP then asks whether to continue with the next step or stop. A failure never closes UDP. If you stop, the remaining steps are marked as skipped, and the temporary folder is still cleaned up.

## One restart

UDP asks for a single restart at the end:
- Win11Debloat has no reboot prompt.
- winget installs run with `--silent`.
- Edge removal does not restart Windows.
- The interactive tools are closed by you.

If you choose "Restart now", Windows restarts after 10 seconds. Run `shutdown /a` to cancel.
