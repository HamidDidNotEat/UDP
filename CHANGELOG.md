# Changelog

All notable changes to UDP are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-03

### Added

- **Wizard:** WPF wizard driven by Windows PowerShell 5.1. It has a welcome page and disclaimer, one page per tool, a summary, a run page with progress and an embedded log panel, and a results page with a single restart.
- **Runner:** steps run in a background runspace, so the window stays responsive. A failed step asks whether to continue or stop instead of ending the run.
- **Dry-run mode** (`-DryRun` or the welcome-page checkbox).
- **Restore point:** created before any change. System Protection on the system drive is switched on if needed, and the 24-hour restore point limit is handled.
- **Steps:**
  - Win11Debloat (recommended defaults or custom options, never `-ForceRemoveEdge`)
  - O&O ShutUp10++ (GUI, or silent with your own exported file)
  - Bulk Crap Uninstaller (interactive, run once or keep installed)
  - Alternative browser: Firefox, Chrome or Brave, with optional privacy extensions through the `ExtensionSettings` policy, a revert option, and Settings > Default apps
  - Edge removal with AveYo's script, always keeping WebView2
  - NVCleanstall (NVIDIA GPUs only)
  - Autoruns
- **config/tools.json:** the single file with every source, winget ID, expected signer and integrity method.
- **Verification:** Authenticode signer checks for signed tools; SHA256 checks for Win11Debloat (release `SHA256SUMS`), BCU (GitHub asset digest) and the pinned Edge removal script.
- **Launchers:** `Run-UDP.bat`; `Get.ps1` for the one-liner, which verifies the release zip against its `SHA256SUMS`; and a release workflow that builds both files.
- **Documentation:** README, one page per tool, order of operations and an undo guide.
- **Tests:** `tests/Test-UDP.ps1` checks syntax, encoding, config, XAML, online compatibility and a headless dry run.
