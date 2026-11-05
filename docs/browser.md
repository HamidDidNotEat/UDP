# Alternative browser and privacy extensions

UDP installs another browser **before** Edge is removed, so you are never left without one.

| Browser | winget ID | Fallback direct download | Expected signer |
|---------|-----------|--------------------------|-----------------|
| Mozilla Firefox (recommended, preselected) | `Mozilla.Firefox` | `download.mozilla.org` (latest, 64-bit, en-US), silent `/S` | Mozilla Corporation |
| Google Chrome | `Google.Chrome` | `dl.google.com` enterprise MSI, `msiexec /qn /norestart` | Google LLC |
| Brave | `Brave.Brave` | GitHub `brave/brave-browser` latest `BraveBrowserStandaloneSilentSetup.exe` | Brave Software, Inc. |

If the browser is already installed, the installation is skipped and only the options below are applied.

## Privacy extensions through browser policies

With *Install privacy extensions* ticked, UDP sets the browser's own enterprise policy **`ExtensionSettings`**. The browser then installs the extensions by itself, from its official store.

UDP uses **`installation_mode: normal_installed`** for every extension:
- **Firefox:** installs the extension automatically, and the user can disable it.
- **Chrome / Brave:** installs the extension automatically, and the user can disable it. Google's documentation does not say whether the user can also remove it; revert the policy to manage the extension normally again.

The alternative, `force_installed`, prevents the user from removing or disabling the extension. UDP does not use it.

### Firefox

- **Registry:** `HKLM\SOFTWARE\Policies\Mozilla\Firefox\ExtensionSettings`, type `REG_MULTI_SZ`, containing JSON ([Mozilla documentation](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/)).
- **Extensions:**
  - **uBlock Origin**, ID `uBlock0@raymondhill.net`, `install_url` `https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi`
  - **Privacy Badger**, ID `jid1-MnnxcxisBPnSXQ@jetpack`, `install_url` `https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi`
- **Result:** Firefox shows *"Your browser is being managed by your organization"* in its settings.

### Chrome

- **uBlock Origin no longer works in Chrome:** Manifest V2 extensions were removed. UDP installs **uBlock Origin Lite** instead.
- **Registry:** `HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionSettings`, type `REG_SZ`, containing JSON, with `update_url` `https://clients2.google.com/service/update2/crx` (the Chrome Web Store) ([Google documentation](https://support.google.com/chrome/a/answer/9867568)).
- **Extensions:**
  - **uBlock Origin Lite**, ID `ddkjiahejlhfcafbddmgiahcphecmpfh`
  - **Privacy Badger**, ID `pkehgijcmpdhfbdbbnkijodmdjhbjlgp`
- **Result:** Chrome shows *"Managed by your organization"*.
- **Unmanaged PCs:** on Windows PCs that are not joined to a domain, Chrome only installs extensions from the Chrome Web Store through policy. Both extensions come from there.

### Brave

- **Shields:** Brave already blocks ads and trackers, so the extensions are optional and **unticked by default**.
- **The full uBlock Origin** still runs in Brave, but only as a copy hosted by Brave that you switch on yourself in Brave's extension settings (Manifest V2 section). There is no documented way to install that copy through policy.
- **Through policy,** UDP can add **uBlock Origin Lite** and **Privacy Badger** (same IDs as Chrome).
- **Registry:** `HKLM\SOFTWARE\Policies\BraveSoftware\Brave\ExtensionSettings`. Brave supports the Chromium policies ([Brave documentation](https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy)).

### What "managed" means

Any policy under `HKLM\SOFTWARE\Policies` makes the browser say it is managed. It only means a policy is set on this PC. Nothing is reported to anyone, and nobody can control the browser remotely through it.

### Existing policies are respected

- **Before writing:** UDP reads the current `ExtensionSettings` value and adds only its own extension IDs. An extension that an existing policy already configures is left unchanged.
- **Recorded:** every ID UDP adds is written to `%ProgramData%\UDP\state.json`.

## Taskbar: Edge replaced by the new browser

With *Replace Edge with this browser on the taskbar* ticked (the default), UDP sets the **taskbar layout policy** built into Windows, the method [Microsoft documents for organisations](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps):

- **What UDP writes:** the file `C:\ProgramData\UDP\TaskbarLayout.xml`, and the two values of the *Start Layout* policy in `HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer`: `StartLayoutFile` (path of the file) and `LockedStartLayout` (1).
- **What the layout says:** `PinListPlacement="Replace"` removes Windows' default pins (Edge among them). File Explorer, the new browser (its Start menu shortcut) and the Microsoft Store are pinned in that order. Apps you pinned yourself stay where they are.
- **You keep control:** every pin carries `PinGeneration="1"`, so you can unpin anything later and Windows does not put it back.
- **When:** Windows applies the layout at your next sign-in, which is the restart at the end of UDP.
- **Supported Windows versions:** Windows 11 24H2 from build 26100.4484 (KB5060829), 22H2/23H2 from build 22621/22631.5549 (KB5060826), and every later version. On older versions the option is unavailable, because Windows would put the pins back at every policy refresh.
- **Existing policies:** if an administrator or another tool already set a taskbar layout, UDP leaves it alone.

## Default apps: the new browser for every link and file type

With *Make this browser the default for all its link and file types* ticked (the default), UDP sets Windows' **default associations policy**, the method [Microsoft documents for organisations](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-applicationdefaults):

- **The types:** UDP reads every link and file type the browser registers with Windows (its `Capabilities` key): the rows *Settings > Default apps* shows for it, for example `http`, `https`, `.htm`, `.html`, `.pdf`, `.svg`, `.webp`, `.xht`, `.xhtml`.
- **What UDP writes:** the file `C:\ProgramData\UDP\DefaultAssociations.xml`, and the policy value `DefaultAssociationsConfiguration` in `HKLM\SOFTWARE\Policies\Microsoft\Windows\System`.
- **Applied once:** every association carries `Suggested="true"`. Windows applies it once per `Version`, at your next sign-in, instead of at every sign-in, so you can still choose other default apps later. Running UDP again with the same browser keeps the `Version`, so your later choices stay; choosing another browser increases it.
- **Requirements:** Windows 11 22H2 or later, on Pro, Enterprise or Education. The policy does not exist on Windows Home: there, and when the option is unticked, UDP opens *Settings > Default apps* at the end of the step and shows the two clicks needed.
- **Never forged:** UDP never writes Windows' protected `UserChoice` settings itself.
- **Existing policies:** if a default associations policy is already set by someone else, UDP leaves it alone and opens Settings instead.

## Revert

On the welcome page, click **Revert browser policies created by UDP**, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\UDP.ps1 -RevertBrowserPolicies
```

The revert:
- removes only the extension IDs listed in `state.json`
- removes the taskbar layout policy values UDP set, and its `TaskbarLayout.xml` (your current pins stay as they are)
- removes the default associations policy value UDP set, and its `DefaultAssociations.xml` (your current default apps stay as they are)
- deletes the `ExtensionSettings` value only if UDP created it and it is now empty
- deletes the policy key only if UDP created it and nothing else is stored in it

Restart the browser afterwards. The extensions themselves stay installed but are no longer managed, so you can remove them normally.

## Default browser

Windows does not allow a program to set the default browser in a clean, supported way. The only way around that is to forge the protected `UserChoice` hash, which UDP does not do.

At the end of this step, UDP opens **Settings > Default apps** (`ms-settings:defaultapps`) and shows what to do:
1. Search for the browser.
2. Click **Set default**.
3. Click Continue in UDP.
