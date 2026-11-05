# Security policy

UDP runs with administrator rights and downloads programs from the internet, so security problems are taken seriously.

## Supported versions

Only the [latest release](https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/releases/latest) receives fixes. The one-liner always installs the latest release.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Report it privately instead:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe the problem, how to reproduce it, and the UDP version and Windows build.

You will get an answer as soon as possible. This is a hobby project maintained in free time, so please allow a few days.

## What counts as a security problem

- A way to make UDP run a file that did not pass its integrity check (signature or SHA256).
- A download source in `config/tools.json` that is not the tool's official source, or that serves something else.
- `Get.ps1` accepting a release archive that does not match its published `SHA256SUMS`.
- UDP leaving the system less secure than intended: for example, policies or permissions that stay behind without being documented.

Problems in the third-party tools themselves (Win11Debloat, O&O ShutUp10++, Bulk Crap Uninstaller, Edge_Removal.bat, NVCleanstall, Autoruns, the browsers) should be reported to their authors. Links are in the [README](README.md#credits).
