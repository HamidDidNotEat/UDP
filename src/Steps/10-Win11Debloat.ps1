# Step 1: Win11Debloat by Raphire (https://github.com/Raphire/Win11Debloat).
# Downloads the latest release, checks it against the release's SHA256SUMS and runs it silently.
# UDP never passes -ForceRemoveEdge (Edge is handled by the Edge removal step) and never passes
# -CreateRestorePoint (UDP has already created one).

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

function Get-UdpWin11DebloatArguments {
    param([hashtable]$Context, [hashtable]$Options)

    $tool = Get-UdpToolConfig -Context $Context -Id 'win11debloat'
    $arguments = @($tool.baseArguments)

    if ($Options.Mode -eq 'Custom') {
        $allowed = @(Get-UdpWin11DebloatOptionsForBuild -Context $Context | ForEach-Object { $_.switch })
        foreach ($switch in @($Options.Switches)) {
            if ($allowed -contains $switch -and $tool.neverPass -notcontains $switch) { $arguments += "-$switch" }
        }
    }
    else {
        $arguments += '-RunDefaults'
    }

    if ($Context.DryRun) { $arguments += '-WhatIf' }
    return $arguments
}

function Get-UdpWin11DebloatPlan {
    param([hashtable]$Context, [hashtable]$Options)
    $arguments = Get-UdpWin11DebloatArguments -Context $Context -Options $Options
    $mode = 'Recommended defaults'
    if ($Options.Mode -eq 'Custom') { $mode = "Custom ($(@($Options.Switches).Count) options)" }
    return @(
        "Mode: $mode",
        'Download the latest release from github.com/Raphire/Win11Debloat and check it against its SHA256SUMS',
        "Run hidden: Win11Debloat.ps1 $($arguments -join ' ')"
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
        return New-UdpStepResult -Status Skipped -Message "$($sumsAsset.name) does not list $($zipAsset.name); skipped for safety."
    }
    if (-not (Test-UdpFileHash -Path $zipPath -ExpectedSha256 $expected)) {
        return New-UdpStepResult -Status Skipped -Message 'The downloaded archive does not match the published SHA256; skipped for safety.'
    }

    $extracted = Join-Path $folder 'extracted'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extracted -Force
    $script = Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter $tool.entryScript | Select-Object -First 1
    if (-not $script) {
        return New-UdpStepResult -Status Failed -Message "$($tool.entryScript) was not found in the release archive."
    }

    $arguments = Get-UdpWin11DebloatArguments -Context $Context -Options $Options
    $arguments = Select-UdpKnownWin11DebloatArguments -ScriptPath $script.FullName -Arguments $arguments

    # Win11Debloat writes its own transcript; keep it next to the UDP logs.
    $logFolder = Join-Path $Context.LogDir 'Win11Debloat'
    if (-not (Test-Path -LiteralPath $logFolder)) { New-Item -ItemType Directory -Path $logFolder -Force | Out-Null }
    $arguments += @('-LogPath', $logFolder)

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $exitCode = Invoke-UdpProcess -FilePath $powershell -Label 'Win11Debloat' -WorkingDirectory $script.DirectoryName -ArgumentList (
        @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script.FullName) + $arguments)

    # Win11Debloat restarts Explorer at the end; make sure it is running again.
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

    if ($exitCode -ne 0) {
        return New-UdpStepResult -Status Failed -Message "Win11Debloat exited with code $exitCode. Its own log is in $logFolder."
    }
    $note = "Win11Debloat $($release.tag_name) finished. Its own log is in $logFolder."
    if ($Context.DryRun) { $note = "Win11Debloat $($release.tag_name) ran in preview mode (-WhatIf); nothing was changed." }
    return New-UdpStepResult -Status Success -Message $note
}
