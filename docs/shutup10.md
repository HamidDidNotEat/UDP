# O&O ShutUp10++

- **Author:** O&O Software GmbH
- **Source:** <https://www.oo-software.com/en/shutup10> (freeware)
- **How UDP gets it:**
  - First choice: the vendor's direct download `https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe`. It must be Authenticode-signed by **O&O Software GmbH**, otherwise the step is skipped.
  - Fallback: winget package `OO-Software.ShutUp10`, uninstalled again at the end.
  - It is portable, so the direct download leaves nothing installed. Set `preferredSource` to `"winget"` in `config/tools.json` to try winget first.

## What it does

ShutUp10++ shows Windows privacy, telemetry and app-permission settings as a list of switches. Each setting carries a recommendation:

- **Green (recommended):** safe for almost everyone.
- **Yellow (limited recommendation):** read the description first.
- **Red (not recommended):** can turn off features you use (for example parts of Windows Update, OneDrive or the Store).

## Modes in UDP

**GUI (default).** UDP shows a short guide, opens ShutUp10++, and continues automatically when you close it. Suggested use:
1. *Actions > Apply only recommended settings*.
2. Optionally review the yellow items one by one.
3. If ShutUp10++ offers to create a restore point, you can decline: UDP already made one.

**Silent (with your own settings).** UDP runs `OOSU10.exe <your file>.cfg /quiet`, the syntax that ShutUp10++ writes into the header of the files it exports.

O&O does not publish the settings file format or the list of setting IDs. So UDP **does not ship a settings file** and invents nothing. To enable silent mode:
1. Run UDP once with ShutUp10++ in GUI mode, or run `OOSU10.exe` yourself.
2. Set everything up the way you like.
3. Use *File > Export settings* and save the file as `config\ooshutup10.cfg` in the UDP folder.

The "Silent" option on the ShutUp10++ page then becomes available. If you start UDP with the one-liner, the file must be in your own fork of the repository, because the one-liner downloads the release from GitHub.

## How to undo

- Open ShutUp10++ again and use *Actions > Undo all changes*.
- Or use the System Restore point UDP created at the start.
