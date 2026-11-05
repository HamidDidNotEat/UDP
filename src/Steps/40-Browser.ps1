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
    if ($Options.Taskbar) {
        $lines += "Taskbar: replace Edge with $($browser.name) through the taskbar layout policy, applied at the next sign-in (you can still unpin anything later)"
    }
    if ($Options.SetDefault -and (Test-UdpDefaultAssociationsSupported -Context $Context).Available) {
        $lines += "Default apps: make $($browser.name) the default for all its link and file types through the default associations policy, applied once at the next sign-in"
    }
    else {
        $lines += 'Open Settings > Default apps so you can choose your default browser'
    }
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
    if ($state.BrowserPolicies.Count -eq 0 -and $state.SystemPolicies.Count -eq 0) {
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

    # Windows policies (taskbar layout, default apps): remove only the values UDP created, and its file.
    foreach ($entry in $state.SystemPolicies) {
        foreach ($valueName in $entry.Values) {
            if (Get-ItemProperty -Path $entry.Key -Name $valueName -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $entry.Key -Name $valueName -ErrorAction SilentlyContinue
                $removed++
                Write-UdpLog "Removed the policy value $valueName from $($entry.Key) ($($entry.Name))" -Level Info
            }
        }
        if ($entry.File -and (Test-Path -LiteralPath $entry.File)) {
            Remove-Item -LiteralPath $entry.File -Force -ErrorAction SilentlyContinue
            Write-UdpLog "Removed $($entry.File)" -Level Info
        }
    }

    Save-UdpState -State @{ BrowserPolicies = @(); SystemPolicies = @() }
    Write-UdpLog "Browser policy revert finished: $removed policy entries removed. Restart the browser, and sign out and in again, to apply." -Level Success
    return $removed
}

# Sets a Windows policy value for UDP. If the value already holds something else (set by an
# administrator or another tool), nothing is changed and $false is returned.
function Set-UdpPolicyValue {
    param([string]$Key, [string]$Name, $Value, [ValidateSet('String', 'ExpandString', 'DWord')][string]$Type)
    $current = Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue
    if ($current -and [string]$current.$Name -ne [string]$Value) {
        Write-UdpLog "$Name in $Key is already set to '$($current.$Name)' by someone else; UDP leaves it alone." -Level Warning
        return $false
    }
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }
    New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-UdpLog "Policy: $Name = $Value in $Key" -Level Info
    return $true
}

# Records (or updates) a Windows policy UDP set, so the revert can remove it.
function Add-UdpSystemPolicyState {
    param([hashtable]$Entry)
    $state = Get-UdpState
    $state.SystemPolicies = @($state.SystemPolicies | Where-Object { $_.Name -ne $Entry.Name }) + @($Entry)
    Save-UdpState -State $state
}

# ---------------------------------------------------------------- taskbar

# Windows 11 builds where pins set by the taskbar layout policy can be unpinned for good
# (PinGeneration): 24H2 with KB5060829 (26100.4484), 22H2/23H2 with KB5060826 (22621/22631.5549),
# and every later version. Older builds would put the pins back at every policy refresh.
function Test-UdpTaskbarLayoutSupported {
    param([hashtable]$Context)
    $build = [int]$Context.System.Build
    $ubr = [int]$Context.System.UBR
    if ($build -ge 26200) { return $true }
    if ($build -eq 26100) { return ($ubr -ge 4484) }
    if ($build -eq 22621 -or $build -eq 22631) { return ($ubr -ge 5549) }
    return $false
}

# The browser's own Start menu shortcut: the taskbar layout pins desktop apps by their shortcut.
function Get-UdpBrowserShortcut {
    param($Browser)
    $targets = @($Browser.exePaths | ForEach-Object { (Expand-UdpPath $_).ToLowerInvariant() })
    $shell = New-Object -ComObject WScript.Shell
    foreach ($folder in @([Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Programs'))) {
        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
            $target = [string]$shell.CreateShortcut($file.FullName).TargetPath
            if ($targets -contains $target.ToLowerInvariant()) { return $file.FullName }
        }
    }
    return $null
}

function New-UdpTaskbarLayoutXml {
    param([object[]]$Pins)
    $lines = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<!-- Written by Ultimate Debloat Pack (UDP). Remove it with "Revert browser policies created by UDP". -->',
        '<LayoutModificationTemplate',
        '    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"',
        '    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"',
        '    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"',
        '    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"',
        '    Version="1">',
        '  <CustomTaskbarLayoutCollection PinListPlacement="Replace">',
        '    <defaultlayout:TaskbarLayout>',
        '      <taskbar:TaskbarPinList>'
    )
    foreach ($pin in $Pins) {
        $id = [System.Security.SecurityElement]::Escape([string]$pin.id)
        switch ($pin.type) {
            'DesktopApp' { $lines += "        <taskbar:DesktopApp DesktopApplicationID=`"$id`" PinGeneration=`"1`"/>" }
            'DesktopLink' { $lines += "        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$id`" PinGeneration=`"1`"/>" }
            'UWA' { $lines += "        <taskbar:UWA AppUserModelID=`"$id`" PinGeneration=`"1`"/>" }
        }
    }
    $lines += @('      </taskbar:TaskbarPinList>', '    </defaultlayout:TaskbarLayout>', '  </CustomTaskbarLayoutCollection>', '</LayoutModificationTemplate>')
    return ($lines -join "`r`n")
}

# Replaces Edge with the new browser on the taskbar through the taskbar layout policy, the method
# documented for organisations. Windows applies it at the next sign-in. Every pin carries
# PinGeneration="1", so you can unpin anything later and Windows does not put it back.
# Returns a short note for the step result.
function Set-UdpTaskbarLayout {
    param([hashtable]$Context, [string]$BrowserId, $Browser)

    $layout = (Get-UdpToolConfig -Context $Context -Id 'browser').taskbarLayout
    if (-not (Test-UdpTaskbarLayoutSupported -Context $Context)) {
        Write-UdpLog 'Taskbar: this Windows version cannot apply a taskbar layout that you can change later; the taskbar is left as it is.' -Level Warning
        return 'Taskbar not changed (needs a newer Windows 11).'
    }

    $shortcut = Get-UdpBrowserShortcut -Browser $Browser
    if (-not $shortcut) {
        if (-not $Context.DryRun) {
            Write-UdpLog "Taskbar: no Start menu shortcut of $($Browser.name) was found to pin; the taskbar is left as it is." -Level Warning
            return 'Taskbar not changed (no Start menu shortcut found).'
        }
        $shortcut = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) "$($Browser.name).lnk"
    }

    $pins = @()
    foreach ($pin in $layout.pins) {
        if ($pin.type -eq 'Browser') { $pins += [pscustomobject]@{ type = 'DesktopLink'; id = $shortcut } }
        else { $pins += $pin }
    }
    $xml = New-UdpTaskbarLayoutXml -Pins $pins
    $file = Join-Path $env:ProgramData "UDP\$($layout.fileName)"
    $values = @(
        @{ Name = 'StartLayoutFile'; Value = $file; Type = 'ExpandString' },
        @{ Name = 'LockedStartLayout'; Value = 1; Type = 'DWord' }
    )

    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would write $file and set StartLayoutFile and LockedStartLayout in $($layout.policyKey):`r`n$xml" -Level DryRun
        return 'Dry run: taskbar not changed.'
    }

    # Respect a taskbar layout set by an administrator or another tool.
    foreach ($value in $values) {
        $current = Get-ItemProperty -Path $layout.policyKey -Name $value.Name -ErrorAction SilentlyContinue
        if ($current -and [string]$current.($value.Name) -ne [string]$value.Value) {
            Write-UdpLog "Taskbar: $($value.Name) is already set to '$($current.($value.Name))' by someone else; UDP leaves the taskbar alone." -Level Warning
            return 'Taskbar not changed (a taskbar layout policy already exists).'
        }
    }

    $folder = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($value in $values) {
        Set-UdpPolicyValue -Key $layout.policyKey -Name $value.Name -Value $value.Value -Type $value.Type | Out-Null
    }
    Add-UdpSystemPolicyState -Entry @{ Name = 'TaskbarLayout'; Key = $layout.policyKey; Values = @('StartLayoutFile', 'LockedStartLayout'); File = $file; Version = 1; Browser = $BrowserId }
    return "Taskbar: Edge is replaced by $($Browser.name) at the next sign-in."
}

# ---------------------------------------------------------------- default apps

# The default associations policy exists on Pro, Enterprise and Education (not Home), and applying
# each association only once ("Suggested") needs Windows 11 22H2 or later.
function Test-UdpDefaultAssociationsSupported {
    param([hashtable]$Context)
    if ([string]$Context.System.EditionID -like 'Core*') {
        return New-UdpAvailability $false 'needs Windows Pro, Enterprise or Education (this PC runs Windows Home)'
    }
    if ([int]$Context.System.Build -lt 22621) { return New-UdpAvailability $false 'needs Windows 11 version 22H2 or later' }
    return New-UdpAvailability $true
}

# The link and file types the browser registers with Windows (its Capabilities key), which are the
# rows Settings > Default apps shows for it.
function Get-UdpBrowserAssociations {
    param($Browser)
    $roots = @('HKLM:\SOFTWARE\Clients\StartMenuInternet', 'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet', 'HKCU:\SOFTWARE\Clients\StartMenuInternet')
    $skip = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
    foreach ($root in $roots) {
        foreach ($key in (Get-ChildItem -Path $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like $Browser.startMenuInternet })) {
            $capabilities = Join-Path $key.PSPath 'Capabilities'
            if (-not (Test-Path -LiteralPath $capabilities)) { continue }
            $name = [string](Get-ItemProperty -LiteralPath $capabilities -ErrorAction SilentlyContinue).ApplicationName
            if (-not $name -or $name.StartsWith('@')) { $name = $Browser.name }
            $list = @()
            foreach ($subKey in 'URLAssociations', 'FileAssociations') {
                $values = Get-ItemProperty -LiteralPath (Join-Path $capabilities $subKey) -ErrorAction SilentlyContinue
                if (-not $values) { continue }
                foreach ($property in $values.PSObject.Properties) {
                    if ($skip -contains $property.Name -or -not $property.Value) { continue }
                    $list += [pscustomobject]@{ Identifier = $property.Name; ProgId = [string]$property.Value }
                }
            }
            if ($list.Count -gt 0) { return [pscustomobject]@{ ApplicationName = $name; Associations = $list } }
        }
    }
    return $null
}

function New-UdpDefaultAssociationsXml {
    param($Associations, [int]$Version)
    $application = [System.Security.SecurityElement]::Escape([string]$Associations.ApplicationName)
    $lines = @(
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!-- Written by Ultimate Debloat Pack (UDP). Suggested="true": applied once per Version, so you can change your defaults later. -->',
        "<DefaultAssociations Version=`"$Version`">"
    )
    foreach ($association in $Associations.Associations) {
        $identifier = [System.Security.SecurityElement]::Escape([string]$association.Identifier)
        $progId = [System.Security.SecurityElement]::Escape([string]$association.ProgId)
        $lines += "  <Association Identifier=`"$identifier`" ProgId=`"$progId`" ApplicationName=`"$application`" Suggested=`"true`" />"
    }
    $lines += '</DefaultAssociations>'
    return ($lines -join "`r`n")
}

# Makes the browser the default for every type it registers, through the default associations
# policy (the method documented for organisations). UDP never writes Windows' protected
# UserChoice settings itself. Returns a note when the policy is set, or $null when the user should
# choose in Settings instead (Windows Home, older Windows, or a policy set by someone else).
function Set-UdpDefaultAssociations {
    param([hashtable]$Context, [string]$BrowserId, $Browser)

    $config = (Get-UdpToolConfig -Context $Context -Id 'browser').defaultAssociations
    $support = Test-UdpDefaultAssociationsSupported -Context $Context
    if (-not $support.Available) {
        Write-UdpLog "Default apps: the policy $($support.Reason); UDP opens Settings instead." -Level Info
        return $null
    }

    $associations = Get-UdpBrowserAssociations -Browser $Browser
    if (-not $associations) {
        if ($Context.DryRun) {
            Write-UdpLog "[dry run] would read the link and file types $($Browser.name) registers and make it their default through the default associations policy" -Level DryRun
            return 'Dry run: default apps not changed.'
        }
        Write-UdpLog "Default apps: $($Browser.name) has not registered its link and file types with Windows; UDP opens Settings instead." -Level Warning
        return $null
    }

    # Same browser and same types as last time: keep the Version, so Windows does not apply the
    # defaults again over choices you made since. Anything else: next Version, applied once.
    $file = Join-Path $env:ProgramData "UDP\$($config.fileName)"
    $previous = (Get-UdpState).SystemPolicies | Where-Object { $_.Name -eq 'DefaultAssociations' } | Select-Object -First 1
    $version = 1
    if ($previous -and $previous.Version -gt 0) { $version = $previous.Version }
    $xml = New-UdpDefaultAssociationsXml -Associations $associations -Version $version
    $unchanged = (Test-Path -LiteralPath $file) -and ([System.IO.File]::ReadAllText($file) -eq $xml)
    if ($previous -and -not $unchanged) {
        $version = $previous.Version + 1
        $xml = New-UdpDefaultAssociationsXml -Associations $associations -Version $version
    }
    $types = ($associations.Associations | ForEach-Object { $_.Identifier }) -join ', '

    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would write $file and set $($config.valueName) in $($config.policyKey) ($types):`r`n$xml" -Level DryRun
        return 'Dry run: default apps not changed.'
    }

    $current = Get-ItemProperty -Path $config.policyKey -Name $config.valueName -ErrorAction SilentlyContinue
    if ($current -and [string]$current.($config.valueName) -ne $file) {
        Write-UdpLog "Default apps: $($config.valueName) is already set to '$($current.($config.valueName))' by someone else; UDP opens Settings instead." -Level Warning
        return $null
    }

    $folder = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding($false)))
    Set-UdpPolicyValue -Key $config.policyKey -Name $config.valueName -Value $file -Type String | Out-Null
    Add-UdpSystemPolicyState -Entry @{ Name = 'DefaultAssociations'; Key = $config.policyKey; Values = @($config.valueName); File = $file; Version = $version; Browser = $BrowserId }
    Write-UdpLog "Default apps: $($Browser.name) becomes the default for $types at the next sign-in." -Level Info
    return "Default apps: $($Browser.name) becomes the default for its $($associations.Associations.Count) link and file types at the next sign-in."
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

    # 3. Taskbar: Edge's pin replaced by the new browser (applied at the next sign-in)
    if ($Options.Taskbar) {
        $notes += (Set-UdpTaskbarLayout -Context $Context -BrowserId $Options.Browser -Browser $browser)
    }

    # 4. Default browser: through the default associations policy where Windows supports it,
    #    otherwise you choose it in Settings.
    $defaultNote = $null
    if ($Options.SetDefault) {
        $defaultNote = Set-UdpDefaultAssociations -Context $Context -BrowserId $Options.Browser -Browser $browser
    }
    if ($defaultNote) {
        $notes += $defaultNote
    }
    elseif ($Context.DryRun) {
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
