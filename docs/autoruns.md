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
6. Close Autoruns. Changes take effect after the restart at the end.

The first time it runs, Autoruns shows Microsoft's license terms. Read and accept them yourself; UDP does not accept them for you.

## How to undo

- Open Autoruns again and tick the entry back on.
- Or use the System Restore point UDP created at the start.
