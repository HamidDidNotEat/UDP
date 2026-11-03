# Step 4: alternative browser (Firefox, Chrome or Brave) and optional privacy extensions.
# Extensions are added through the browser's own enterprise policy "ExtensionSettings" with
# installation_mode "normal_installed": installed automatically, and you can still disable them.
# UDP records every extension it adds in state.json, so "Revert browser policies" removes
# exactly those and nothing that was configured before.
# The default browser is never changed programmatically: UDP opens Settings > Default apps.

function Test-UdpBrowserAvailable {
    param([hashtable]$Context)
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    return New-UdpAvailability $true
}

function Get-UdpBrowserConfig {
    param([hashtable]$Context, [string]$BrowserId)
    $tool = Get-UdpToolConfig -Context $Context -Id 'browser'
    $browser = $tool.browsers.$BrowserId
    if (-not $browser) { throw "Unknown browser '$BrowserId'." }
    return $browser
}

function Get-UdpSelectedExtensions {
    param($Browser, [hashtable]$Options)
    if (-not $Options.Extensions) { return @() }
    return @($Browser.extensions | Where-Object { @($Options.ExtensionIds) -contains $_.id })
}

function Get-UdpBrowserPlan {
    param([hashtable]$Context, [hashtable]$Options)
    $browser = Get-UdpBrowserConfig -Context $Context -BrowserId $Options.Browser
    $lines = @("Install $($browser.name) with winget ($($browser.winget)), or skip if it is already installed")
    $extensions = @(Get-UdpSelectedExtensions -Browser $browser -Options $Options)
    if ($extensions.Count -gt 0) {
        $lines += "Add extensions through the $($browser.name) ExtensionSettings policy ($($browser.policy.installationMode)): $(($extensions | ForEach-Object { $_.name }) -join ', ')"
        $lines += "Registry: $($browser.policy.key)\$($browser.policy.valueName)"
    }
    $lines += 'Open Settings > Default apps so you can choose your default browser'
    return $lines
}

function Test-UdpBrowserInstalled {
    param($Browser)
    foreach ($path in @($Browser.exePaths)) {
        if (Test-Path -LiteralPath (Expand-UdpPath $path)) { return $true }
    }
    return $false
}

function Install-UdpBrowserDirect {
    param([hashtable]$Context, $Browser)

    $folder = New-UdpWorkFolder -Context $Context -Name 'browser'
    $installer = Join-Path $folder $Browser.direct.fileName
    Invoke-UdpDownload -Uri $Browser.direct.url -OutFile $installer | Out-Null

    $check = Test-UdpSignature -Path $installer -ExpectedSigner $Browser.integrity.expectedSigner
    if (-not $check.Valid) {
        throw (New-Object System.Security.SecurityException("The $($Browser.name) installer failed the signature check ($($check.Reason)); skipped for safety."))
    }

    if ($installer -like '*.msi') {
        $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
        $code = Invoke-UdpProcess -FilePath $msiexec -ArgumentList (@('/i', $installer) + @($Browser.direct.silentArguments)) -Label "$($Browser.name) installer"
    }
    else {
        $code = Invoke-UdpProcess -FilePath $installer -ArgumentList @($Browser.direct.silentArguments) -Label "$($Browser.name) installer"
    }
    # 3010 = success, restart required (Windows Installer).
    return ($code -eq 0 -or $code -eq 3010)
}

# Reads an ExtensionSettings policy value as an object (empty object if the value is not set).
function Read-UdpExtensionPolicy {
    param([string]$Key, [string]$ValueName)
    $item = Get-ItemProperty -Path $Key -Name $ValueName -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $raw = $item.$ValueName
    if ($raw -is [array]) { $raw = $raw -join "`n" }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-UdpExtensionPolicy {
    param([string]$Key, [string]$ValueName, [string]$ValueType, $Policy)
    $json = ConvertTo-Json -InputObject $Policy -Depth 6 -Compress
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }
    if ($ValueType -eq 'MultiString') {
        New-ItemProperty -Path $Key -Name $ValueName -PropertyType MultiString -Value @($json) -Force | Out-Null
    }
    else {
        New-ItemProperty -Path $Key -Name $ValueName -PropertyType String -Value $json -Force | Out-Null
    }
}

function Set-UdpBrowserExtensionPolicy {
    param([hashtable]$Context, [string]$BrowserId, $Browser, [object[]]$Extensions)

    $policy = $Browser.policy
    $state = Get-UdpState
    $entry = $state.BrowserPolicies | Where-Object { $_.Browser -eq $BrowserId -and $_.Key -eq $policy.key -and $_.ValueName -eq $policy.valueName } | Select-Object -First 1
    $ownedBefore = @()
    if ($entry) { $ownedBefore = @($entry.ExtensionIds) }

    $keyExisted = Test-Path -LiteralPath $policy.key
    $current = Read-UdpExtensionPolicy -Key $policy.key -ValueName $policy.valueName
    $valueExisted = [bool]$current
    if (-not $current) { $current = New-Object psobject }

    $added = @()
    foreach ($extension in $Extensions) {
        $existing = $current.PSObject.Properties[$extension.id]
        if ($existing -and $ownedBefore -notcontains $extension.id) {
            Write-UdpLog "$($extension.name) is already configured by an existing policy; UDP leaves it unchanged." -Level Info
            continue
        }
        $settings = [ordered]@{ installation_mode = $policy.installationMode }
        if ($policy.flavor -eq 'firefox') { $settings.install_url = $extension.installUrl }
        else { $settings.update_url = $policy.updateUrl }
        $current | Add-Member -NotePropertyName $extension.id -NotePropertyValue ([pscustomobject]$settings) -Force
        $added += $extension.id
        Write-UdpLog "Policy: $($extension.name) ($($extension.id)) -> $($policy.installationMode)" -Level Info
    }

    if ($added.Count -eq 0) { return }

    if ($Context.DryRun) {
        $json = ConvertTo-Json -InputObject $current -Depth 6 -Compress
        Write-UdpLog "[dry run] would write $($policy.key)\$($policy.valueName) = $json" -Level DryRun
        return
    }

    Write-UdpExtensionPolicy -Key $policy.key -ValueName $policy.valueName -ValueType $policy.valueType -Policy $current

    if ($entry) {
        $entry.ExtensionIds = @(@($entry.ExtensionIds) + $added | Select-Object -Unique)
    }
    else {
        $state.BrowserPolicies += @{
            Browser      = $BrowserId
            Key          = $policy.key
            ValueName    = $policy.valueName
            ValueType    = $policy.valueType
            ExtensionIds = $added
            CreatedValue = (-not $valueExisted)
            CreatedKey   = (-not $keyExisted)
        }
    }
    Save-UdpState -State $state
}

# Removes the extension policies UDP created (used by the welcome page button and -RevertBrowserPolicies).
function Remove-UdpBrowserPolicies {
    param([hashtable]$Context)

    $state = Get-UdpState
    if ($state.BrowserPolicies.Count -eq 0) {
        Write-UdpLog 'No browser policies created by UDP were found.' -Level Info
        return 0
    }

    $removed = 0
    foreach ($entry in $state.BrowserPolicies) {
        $current = Read-UdpExtensionPolicy -Key $entry.Key -ValueName $entry.ValueName
        if ($current) {
            foreach ($id in $entry.ExtensionIds) {
                if ($current.PSObject.Properties[$id]) {
                    $current.PSObject.Properties.Remove($id)
                    $removed++
                    Write-UdpLog "Removed policy for $id from $($entry.Key)\$($entry.ValueName)" -Level Info
                }
            }
            if (@($current.PSObject.Properties).Count -eq 0 -and $entry.CreatedValue) {
                Remove-ItemProperty -Path $entry.Key -Name $entry.ValueName -ErrorAction SilentlyContinue
                Write-UdpLog "Removed $($entry.Key)\$($entry.ValueName) (UDP had created it)" -Level Info
            }
            else {
                Write-UdpExtensionPolicy -Key $entry.Key -ValueName $entry.ValueName -ValueType $entry.ValueType -Policy $current
            }
        }
        # Remove the policy key only if UDP created it and nothing else is stored in it now.
        if ($entry.CreatedKey -and (Test-Path -LiteralPath $entry.Key)) {
            $key = Get-Item -LiteralPath $entry.Key
            if ($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0) {
                Remove-Item -LiteralPath $entry.Key -Force -ErrorAction SilentlyContinue
                Write-UdpLog "Removed the empty key $($entry.Key)" -Level Info
            }
        }
    }

    Save-UdpState -State @{ BrowserPolicies = @() }
    Write-UdpLog "Browser policy revert finished: $removed extension entries removed. Restart the browser to apply." -Level Success
    return $removed
}

function Get-UdpDefaultBrowserBriefing {
    param([string]$BrowserName)
    return @"
Windows does not let programs set the default browser for you (on purpose), so UDP opened Settings > Default apps.

  1. In the search box at the top, type "$BrowserName" and select it.
  2. Click "Set default" at the top of the page.
  3. Close Settings, then click Continue here.
"@
}

function Invoke-UdpBrowser {
    param([hashtable]$Context, [hashtable]$Options)

    $browser = Get-UdpBrowserConfig -Context $Context -BrowserId $Options.Browser
    $notes = @()

    # 1. Install
    if (Test-UdpBrowserInstalled -Browser $browser) {
        Write-UdpLog "$($browser.name) is already installed; installation skipped." -Level Info
        $notes += "$($browser.name) was already installed."
    }
    else {
        $installed = $false
        if (Get-UdpWingetPath) {
            $install = Install-UdpWingetPackage -Context $Context -Id $browser.winget
            $installed = $install.Success
            if (-not $installed) { Write-UdpLog "winget could not install $($browser.name) (exit code $($install.ExitCode)); trying the official direct download." -Level Warning }
        }
        if (-not $installed) {
            if ($Context.DryRun) {
                Write-UdpLog "[dry run] would download and install $($browser.name) from $($browser.direct.url)" -Level DryRun
                $installed = $true
            }
            else {
                try { $installed = Install-UdpBrowserDirect -Context $Context -Browser $browser }
                catch [System.Security.SecurityException] { return New-UdpStepResult -Status Skipped -Message $_.Exception.Message }
            }
        }
        if (-not $Context.DryRun -and -not (Test-UdpBrowserInstalled -Browser $browser)) {
            return New-UdpStepResult -Status Failed -Message "$($browser.name) could not be installed."
        }
        $notes += "$($browser.name) installed."
    }

    # 2. Extensions
    $extensions = @(Get-UdpSelectedExtensions -Browser $browser -Options $Options)
    if ($extensions.Count -gt 0) {
        Set-UdpBrowserExtensionPolicy -Context $Context -BrowserId $Options.Browser -Browser $browser -Extensions $extensions
        $notes += "Extensions added by policy: $(($extensions | ForEach-Object { $_.name }) -join ', ')."
    }

    # 3. Default browser (the user does it in Settings)
    if ($Context.DryRun) {
        Write-UdpLog '[dry run] would open Settings > Default apps with instructions' -Level DryRun
    }
    else {
        $tool = Get-UdpToolConfig -Context $Context -Id 'browser'
        Start-Process $tool.defaultAppsUri
        Request-UdpDecision -Context $Context -Kind 'Info' -Title "Make $($browser.name) your default browser" -Body (Get-UdpDefaultBrowserBriefing -BrowserName $browser.name) -Buttons @(
            (New-UdpButton 'continue' 'Continue' -Primary)) | Out-Null
    }

    return New-UdpStepResult -Status Success -Message ($notes -join ' ')
}
