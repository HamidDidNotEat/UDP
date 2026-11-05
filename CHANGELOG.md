# Changelog

All notable changes to Ultimate Debloat Pack are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.5] - 2026-11-05

### Added

- **Choose which apps Win11Debloat removes.** The Win11Debloat page lists the apps found on this PC, from Win11Debloat's own list in the release that will run, grouped by its recommendation: safe to remove, optional, not recommended. The list starts with Win11Debloat's recommended selection; "Recommended selection" and "Select none" reset it, and apps that are not installed can be shown too. Point at an app to see what it is.
- Recommended settings work with your own app choice: UDP then runs Win11Debloat with `-RunDefaultsLite -RemoveApps -Apps <your list>`.

### Changed

- The custom options no longer include "Remove the default selection of apps" and "Remove the Xbox app and Xbox Game Bar": the app list covers both.
- Microsoft Edge is never offered in the app list. UDP's own Edge removal step handles it.
- Win11Debloat is downloaded and verified once, when UDP starts, and reused for the run.

## [0.1.4] - 2026-11-05

### Added

- **Autoruns guide: what is usually safe to switch off** (chat apps and game launchers you open yourself, music apps, unused cloud sync, meeting apps, update checkers of rarely used apps, leftovers) **and what to leave on** (hardware makers' software, security software, anti-cheat, drivers, anything you do not recognise).

## [0.1.3] - 2026-11-05

### Changed

- **Clearer guides before each tool opens.** The guides for ShutUp10++, Bulk Crap Uninstaller, NVCleanstall and Autoruns now have headings, numbered steps, a "Do I need to save?" answer and what to do when you are done. For example, Autoruns has no Save button: unticking an entry is enough.
- The guides are shown formatted (headings, numbered steps, highlighted notes) in a wider panel, and the log folds away while a guide is open.

## [0.1.2] - 2026-11-05

### Added

- **Edge removal cleans up Edge's shortcuts.** Once Edge is gone, UDP removes the **Microsoft Edge** shortcuts left on the desktop (yours and the all-users one) and in the Start menu. They only opened a small empty window. Only shortcuts pointing to Edge's `msedge.exe` are removed.
- Running UDP again on a PC where Edge was already removed now cleans up those leftover shortcuts too.

## [0.1.1] - 2026-11-05

### Fixed

- **Edge removal no longer reports "Failed" when Edge was removed.** Edge's own uninstaller keeps running in the background after AveYo's script ends, and UDP checked too early. UDP now waits up to 5 minutes for it to finish, then checks both Edge's entry in *Settings > Apps* and `msedge.exe`. When something is really left, the log says exactly what.
- Terminal colour codes printed by some tools no longer appear as garbage characters in the log.

## [0.1.0] - 2026-11-05

First public release.

### Added

- **Wizard:** WPF wizard driven by Windows PowerShell 5.1, with a welcome page and disclaimer, one page per tool, a summary, a run page with progress and an embedded log panel, and a results page with a single restart.
- **Runner:** steps run in a background runspace, so the window stays responsive. A failed step asks whether to continue or stop instead of ending the run.
- **Dry-run mode** (`-DryRun` or the welcome-page checkbox).
- **Restore point** before any change. System Protection on the system drive is switched on if needed, and the 24-hour restore point limit is handled.
- **Steps:** Win11Debloat (recommended defaults or custom options, never `-ForceRemoveEdge`), O&O ShutUp10++ (its own window, or silent with your exported file), Bulk Crap Uninstaller (interactive, run once or keep installed), alternative browser (Firefox, Chrome or Brave, optional privacy extensions through the `ExtensionSettings` policy, with a revert option), Edge removal with AveYo's script (WebView2 always kept), NVCleanstall (NVIDIA GPUs only) and Autoruns.
- **`config/tools.json`:** the single file with every source, winget ID, expected signer and integrity method.
- **Verification:** Authenticode signer checks for signed tools; SHA256 checks for Win11Debloat (release `SHA256SUMS`), Bulk Crap Uninstaller (GitHub asset digest) and the pinned Edge removal script.
- **Launchers:** `Run-UDP.bat`, and `Get.ps1` for the one-liner, which verifies the release zip against its `SHA256SUMS`.
- **Repository:** logo, README with badges, contributing guide, security policy, code of conduct, issue and pull request templates, test workflow on every push, and release notes taken from this changelog.
- **Documentation:** one page per tool, order of operations and an undo guide.
- **Tests:** `tests/Test-UDP.ps1` checks syntax, encoding, config, XAML, online compatibility and a headless dry run.

### Known issues

Found during the first virtual machine test, planned for the next releases:

- Edge removal can report "Failed" although Edge was removed: the result is checked before Edge's own uninstaller has finished.
- Edge shortcuts (desktop, Start menu) stay behind after Edge removal and open an empty window.

[Unreleased]: https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/releases/tag/v0.1.0
