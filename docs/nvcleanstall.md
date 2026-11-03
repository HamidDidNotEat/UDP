# NVCleanstall

- **Author:** TechPowerUp
- **Source:** <https://www.techpowerup.com/nvcleanstall/> (freeware)
- **winget ID:** `TechPowerUp.NVCleanstall`
- **Offered only when** an NVIDIA graphics card is detected (`Win32_VideoController`). **Default:** off.

## What it does

NVCleanstall downloads the official driver from NVIDIA and builds an installer with only the components you choose. It leaves out telemetry, the NVIDIA App and other extras. It is interactive: UDP shows a guide, opens NVCleanstall, and continues when you close it.

## How UDP gets it

1. winget installs it (winget checks the installer hash from its manifest). It stays installed so you can use it for future driver updates.
2. If winget is missing or fails:
   - UDP opens the official TechPowerUp download page.
   - You pick the installer you downloaded.
   - UDP checks that it is Authenticode-signed by **TechPowerUp LLC** before running it.

## Recommended choices

**Components:**
- Display driver (always required)
- PhysX (used by some games)
- HD Audio driver: only if your sound goes through HDMI or DisplayPort (TV or monitor speakers)

**Tweaks:**
- Disable installer telemetry and advertising
- Perform a clean installation

## Trade-off: no NVIDIA App

Without the NVIDIA App you lose:
- **DLSS Override**
- **ShadowPlay** (Instant Replay and recording)
- **Smooth Motion**

Alternatives:
- [NVIDIA Profile Inspector](https://github.com/Orbmu2k/nvidiaProfileInspector) for per-game driver settings
- [OBS Studio](https://obsproject.com/) for recording

You can install the NVIDIA App later at any time.

## How to undo

- Install the standard driver from <https://www.nvidia.com/drivers>.
- Uninstall NVCleanstall from Settings > Apps if you no longer want it.
