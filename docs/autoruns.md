# Autoruns

- **Author:** Mark Russinovich, Microsoft Sysinternals
- **Source:** <https://learn.microsoft.com/sysinternals/downloads/autoruns> ([Sysinternals license terms](https://learn.microsoft.com/sysinternals/license-terms))
- **How UDP gets it:**
  - First choice: `https://download.sysinternals.com/files/Autoruns.zip`. The program inside must be Authenticode-signed by **Microsoft Corporation**, otherwise the step is skipped. It is portable and deleted at the end.
  - Fallback: winget package `Microsoft.Sysinternals.Autoruns`, uninstalled again at the end.
- **Program used:** `Autoruns64.exe` (64-bit), `Autoruns64a.exe` (ARM64) or `Autoruns.exe` (32-bit).

## What it does

Autoruns lists everything that starts with Windows:
- logon programs
- services and drivers
- scheduled tasks
- Explorer and browser add-ons
- and more

It shows far more than Task Manager. It is a **manual review tool**: nothing changes unless you untick an entry.

## Why it runs last

Autoruns runs after every uninstall (Win11Debloat, BCU, Edge), so it shows only the startup entries that are actually left.

## How to use it (shown again before Autoruns opens)

1. Open **Options** and tick **Hide Microsoft Entries** and **Hide Windows Entries**, then press **F5** to refresh. What is left is third-party software.
2. Start with the **Logon**, **Scheduled Tasks** and **Services** tabs.
3. To stop something from starting, **untick** its checkbox. Do not delete entries: an unticked entry can be ticked again, a deleted one cannot.
4. Colours:
   - **Yellow** rows point to files that no longer exist, usually leftovers.
   - **Pink** rows have no verified publisher: look them up before changing them.
5. Leave drivers, security software and anything you do not recognise alone.
6. Close Autoruns with the X. UDP continues automatically.

## Usually safe to switch off

- Chat apps and game launchers that you open yourself: Discord, Steam, Epic Games, Battle.net, EA app, Ubisoft Connect
- Music and video apps: Spotify, iTunes helpers
- Cloud sync you do not use: OneDrive, Dropbox, Google Drive
- Meeting apps you do not need at startup: Teams, Zoom, Skype
- Update checkers of apps you rarely use (for example Adobe or Java): you then update those apps by opening them
- Yellow entries: their file no longer exists, they are leftovers

## Leave these on

- Anything from your graphics, audio, network, mouse or keyboard maker (NVIDIA, AMD, Intel, Realtek, Logitech, ...)
- Your antivirus or security software, including the Windows Security icon (`SecurityHealth`)
- Game anti-cheat services (Easy Anti-Cheat, BattlEye, Riot Vanguard)
- Everything on the **Drivers** tab
- Anything you do not recognise: look it up first

If something stops working after the restart, open Autoruns again and tick the entry back on.

**Do I need to save?** No. Unticking an entry is applied immediately and takes effect at the next restart. *File > Save* only exports a list of entries for comparing later; you do not need it.

The first time it runs, Autoruns shows Microsoft's license terms. Read and accept them yourself; UDP does not accept them for you.

## How to undo

- Open Autoruns again and tick the entry back on.
- Or use the System Restore point UDP created at the start.
