# Step 1: Win11Debloat by Raphire (https://github.com/Raphire/Win11Debloat).
# Downloads the latest release, checks it against the release's SHA256SUMS and runs it silently.
# UDP never passes -ForceRemoveEdge (Edge is handled by the Edge removal step) and never passes
# -CreateRestorePoint (UDP has already created one). The app list shown in the wizard is read from
# the same release (Config/Apps.json), so it always matches the version that runs.

function Test-UdpWin11DebloatAvailable {
    param([hashtable]$Context)
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    return New-UdpAvailability $true
}

# Custom-mode options from config/tools.json that apply to this Windows build.
function Get-UdpWin11DebloatOptionsForBuild {
    param([Parameter(Mandatory)][hashtable]$Context)
    $build = $Context.System.Build
    $tool = Get-UdpToolConfig -Context $Context -Id 'win11debloat'
    return @($tool.customOptions | Where-Object {
            ((-not $_.minBuild) -or $build -ge $_.minBuild) -and ((-not $_.maxBuild) -or $build -le $_.maxBuild)
        })
}

# Downloads, verifies and extracts the latest release once per UDP session; later calls reuse it.
# A failed checksum throws a SecurityException so the step is skipped, not retried elsewhere.
function Get-UdpWin11DebloatRelease {
    param([Parameter(Mandatory)][hashtable]$Context)

    $cached = $Context.Win11DebloatRelease
    if ($cached -and (Test-Path -LiteralPath $cached.Script)) { return $cached }

    $tool = Get-UdpToolConfig -Context $Context -Id 'win11debloat'
    $folder = New-UdpWorkFolder -Context $Context -Name 'win11debloat'

    $release = Get-UdpGitHubLatestRelease -Repo $tool.githubRelease.repo
    Write-UdpLog "Win11Debloat release: $($release.tag_name)" -Level Info
    $zipAsset = Get-UdpGitHubAsset -Release $release -Name $tool.githubRelease.asset
    $sumsAsset = Get-UdpGitHubAsset -Release $release -Name $tool.githubRelease.checksumsAsset

    $zipPath = Join-Path $folder $zipAsset.name
    $sumsPath = Join-Path $folder $sumsAsset.name
    Invoke-UdpDownload -Uri $sumsAsset.browser_download_url -OutFile $sumsPath | Out-Null
    Invoke-UdpDownload -Uri $zipAsset.browser_download_url -OutFile $zipPath | Out-Null

    $expected = Get-UdpHashFromSums -SumsText ([System.IO.File]::ReadAllText($sumsPath)) -FileName $zipAsset.name
    if (-not $expected) {
        throw (New-Object System.Security.SecurityException("$($sumsAsset.name) does not list $($zipAsset.name); skipped for safety."))
    }
    if (-not (Test-UdpFileHash -Path $zipPath -ExpectedSha256 $expected)) {
        throw (New-Object System.Security.SecurityException('The downloaded Win11Debloat archive does not match the published SHA256; skipped for safety.'))
    }

    $extracted = Join-Path $folder 'extracted'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extracted -Force
    $script = Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter $tool.entryScript | Select-Object -First 1
    if (-not $script) { throw "$($tool.entryScript) was not found in the release archive." }

    $result = [pscustomobject]@{ Tag = $release.tag_name; Root = $script.DirectoryName; Script = $script.FullName }
    $Context.Win11DebloatRelease = $result
    return $result
}

# Reads Win11Debloat's own app list (Config/Apps.json and its English names) from the release and
# marks which apps are installed. Returns $null when it cannot be loaded; the wizard then offers
# Win11Debloat's recommended selection as a whole.
function Get-UdpWin11DebloatCatalog {
    param([Parameter(Mandatory)][hashtable]$Context)

    try {
        $tool = Get-UdpToolConfig -Context $Context -Id 'win11debloat'
        $release = Get-UdpWin11DebloatRelease -Context $Context
        $apps = ([System.IO.File]::ReadAllText((Join-Path $release.Root $tool.appCatalog.apps), [System.Text.Encoding]::UTF8) | ConvertFrom-Json).Apps
        $names = $null
        $namesPath = Join-Path $release.Root $tool.appCatalog.names
        if (Test-Path -LiteralPath $namesPath) {
            $names = [System.IO.File]::ReadAllText($namesPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        }

        # Store apps installed for any user (all users needs administrator rights).
        $installed = @{}
        try { $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
        catch { $packages = @(Get-AppxPackage -ErrorAction SilentlyContinue) }
        foreach ($package in $packages) { $installed[$package.Name] = $true }

        $never = @($tool.neverRemoveApps)
        $entries = @()
        foreach ($app in $apps) {
            $ids = @($app.AppId | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            if ($ids.Count -eq 0) { continue }
            if (@($ids | Where-Object { $never -contains $_ }).Count -gt 0) { continue }

            $name = $ids[0]
            $description = ''
            if ($names -and $names.($ids[0])) {
                $name = $names.($ids[0]).FriendlyName
                $description = $names.($ids[0]).Description
            }
            # Apps that Win11Debloat removes with winget are not checked here; they are always listed.
            $isInstalled = $null
            if ($app.RemovalMethod -eq 'Appx') { $isInstalled = (@($ids | Where-Object { $installed.ContainsKey($_) }).Count -gt 0) }

            $entries += [pscustomobject]@{
                Id             = $ids[0]
                Ids            = $ids
                Name           = $name
                Description    = $description
                Recommendation = [string]$app.Recommendation
                Default        = [bool]$app.SelectedByDefault
                Installed      = $isInstalled
            }
        }
        Write-UdpLog "Win11Debloat app list: $($entries.Count) apps, $(@($entries | Where-Object { $_.Installed -ne $false }).Count) on this PC" -Level Info
        return [pscustomobject]@{ Tag = $release.Tag; Apps = $entries }
    }
    catch {
        Write-UdpLog "Could not load Win11Debloat's app list: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-UdpWin11DebloatArguments {
    param([hashtable]$Context, [hashtable]$Options)

    $tool = Get-UdpToolConfig -Context $Context -Id 'win11debloat'
    $arguments = @($tool.baseArguments)
    $catalog = $Context.Win11DebloatCatalog
    $chosenApps = ($catalog -and $null -ne $Options.Apps)

    # Apps: the list chosen in the wizard, or Win11Debloat's whole recommended selection when its
    # app list could not be loaded. Edge is never passed, whatever the list says.
    $appArguments = @()
    if ($chosenApps) {
        $never = @($tool.neverRemoveApps)
        $apps = @($Options.Apps | Where-Object { $_ -and $never -notcontains $_ })
        if ($apps.Count -gt 0) { $appArguments = @('-RemoveApps', '-Apps', ($apps -join ',')) }
    }
    $defaultApps = (-not $chosenApps -and $Options.RemoveDefaultApps -ne $false)

    if ($Options.Mode -eq 'Custom') {
        $allowed = @(Get-UdpWin11DebloatOptionsForBuild -Context $Context | ForEach-Object { $_.switch })
        foreach ($switch in @($Options.Switches)) {
            if ($allowed -contains $switch -and $tool.neverPass -notcontains $switch) { $arguments += "-$switch" }
        }
        if ($defaultApps) { $arguments += '-RemoveApps' }
        $arguments += $appArguments
    }
    elseif ($chosenApps -and $Options.AppsCustomized) {
        # Recommended settings with your own app choice: -RunDefaultsLite applies Win11Debloat's
        # default settings without removing apps, and -RemoveApps -Apps adds the chosen list.
        $arguments += '-RunDefaultsLite'
        $arguments += $appArguments
    }
    elseif ($chosenApps -or $defaultApps) {
        $arguments += '-RunDefaults'
    }
    else {
        $arguments += '-RunDefaultsLite'
    }

    if ($Context.DryRun) { $arguments += '-WhatIf' }
    return $arguments
}

function Get-UdpWin11DebloatPlan {
    param([hashtable]$Context, [hashtable]$Options)

    $arguments = @(Get-UdpWin11DebloatArguments -Context $Context -Options $Options)
    $catalog = $Context.Win11DebloatCatalog

    $settings = 'Settings: Win11Debloat''s recommended settings'
    if ($Options.Mode -eq 'Custom') { $settings = "Settings: custom ($(@($Options.Switches).Count) options)" }

    if ($catalog -and $null -ne $Options.Apps) {
        $chosen = @($catalog.Apps | Where-Object { @($Options.Apps) -contains $_.Id -and $_.Installed -ne $false })
        if ($chosen.Count -eq 0) { $apps = 'Apps: none removed' }
        else {
            $list = ($chosen | Select-Object -First 8 | ForEach-Object { $_.Name }) -join ', '
            if ($chosen.Count -gt 8) { $list += " and $($chosen.Count - 8) more" }
            $which = 'your selection'
            if (-not $Options.AppsCustomized) { $which = 'Win11Debloat''s recommended selection' }
            $apps = "Apps ($which, $($chosen.Count) on this PC): $list"
        }
    }
    elseif ($Options.RemoveDefaultApps -ne $false) { $apps = 'Apps: Win11Debloat''s recommended selection' }
    else { $apps = 'Apps: none removed' }

    # Show the app list as a count; it is already listed above.
    $display = @()
    for ($i = 0; $i -lt $arguments.Count; $i++) {
        if ($arguments[$i] -eq '-Apps' -and $i + 1 -lt $arguments.Count) {
            $display += "-Apps <$(@($arguments[$i + 1] -split ',').Count) apps>"
            $i++
        }
        else { $display += $arguments[$i] }
    }

    return @(
        $settings,
        $apps,
        'Download the latest release from github.com/Raphire/Win11Debloat and check it against its SHA256SUMS',
        "Run hidden: Win11Debloat.ps1 $($display -join ' ')"
    )
}

# Keeps only switches that the downloaded Win11Debloat.ps1 really declares, so a renamed option
# in a future Win11Debloat release is dropped with a warning instead of breaking the run.
function Select-UdpKnownWin11DebloatArguments {
    param([string]$ScriptPath, [string[]]$Arguments)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    if (-not $ast.ParamBlock) { return $Arguments }
    $known = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    # Common parameters such as -WhatIf are handled by PowerShell itself.
    $known += 'WhatIf'

    $kept = @()
    foreach ($argument in $Arguments) {
        $name = $argument.TrimStart('-')
        if ($argument.StartsWith('-') -and $known -notcontains $name) {
            Write-UdpLog "Win11Debloat does not know -$name any more; this option is skipped." -Level Warning
            continue
        }
        $kept += $argument
    }
    return $kept
}

function Invoke-UdpWin11Debloat {
    param([hashtable]$Context, [hashtable]$Options)

    try {
        $release = Get-UdpWin11DebloatRelease -Context $Context
    }
    catch [System.Security.SecurityException] {
        return New-UdpStepResult -Status Skipped -Message $_.Exception.Message
    }

    $arguments = Get-UdpWin11DebloatArguments -Context $Context -Options $Options
    $arguments = Select-UdpKnownWin11DebloatArguments -ScriptPath $release.Script -Arguments $arguments

    # Win11Debloat writes its own transcript; keep it next to the UDP logs.
    $logFolder = Join-Path $Context.LogDir 'Win11Debloat'
    if (-not (Test-Path -LiteralPath $logFolder)) { New-Item -ItemType Directory -Path $logFolder -Force | Out-Null }
    $arguments += @('-LogPath', $logFolder)

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $exitCode = Invoke-UdpProcess -FilePath $powershell -Label 'Win11Debloat' -WorkingDirectory $release.Root -ArgumentList (
        @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $release.Script) + $arguments)

    # Win11Debloat restarts Explorer at the end; make sure it is running again.
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

    if ($exitCode -ne 0) {
        return New-UdpStepResult -Status Failed -Message "Win11Debloat exited with code $exitCode. Its own log is in $logFolder."
    }
    $note = "Win11Debloat $($release.Tag) finished. Its own log is in $logFolder."
    if ($Context.DryRun) { $note = "Win11Debloat $($release.Tag) ran in preview mode (-WhatIf); nothing was changed." }
    return New-UdpStepResult -Status Success -Message $note
}
