# Step 3: Bulk Crap Uninstaller (https://github.com/BCUninstaller/Bulk-Crap-Uninstaller).
# Interactive only: UDP never uninstalls anything itself and ships no uninstall list.
# "Run once": portable build from the official release, removed with the temp folder at the end.
# "Keep it installed": installed with winget.
# BCU binaries are not Authenticode-signed; see the "integrity" notes in config/tools.json.

function Test-UdpBcuAvailable {
    param([hashtable]$Context)
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    return New-UdpAvailability $true
}

function Get-UdpBcuPlan {
    param([hashtable]$Context, [hashtable]$Options)
    $lines = @()
    if ($Options.Mode -eq 'Install') {
        $lines += 'Install Bulk Crap Uninstaller with winget (Klocman.BulkCrapUninstaller) and keep it installed'
    }
    elseif ($Context.System.TarSupports7z) {
        $lines += 'Download the portable release from GitHub, check its SHA256 digest, use it once and delete it at the end'
    }
    else {
        $lines += 'This Windows cannot extract the portable .7z archive, so BCU is installed with winget and uninstalled at the end'
    }
    $lines += 'Show a short guide, then open BCU and wait until you close it'
    return $lines
}

function Get-UdpBcuBriefing {
    return @'
## What you will see
A list of every desktop program on this PC. The first time, BCU asks a few setup questions: keep the suggested answers.

## Step by step
1. Tick the box next to each program you want to remove. You can tick several.
2. Click "Uninstall" in the toolbar, check the list and confirm.
3. Some programs open their own uninstaller: answer its questions (usually Yes, Remove or Next).
4. When BCU offers to look for leftovers, accept. Remove only the items rated "Very good", check "Good" ones yourself, and leave "Questionable" and "Bad" ones alone. Then click "Delete selected".
5. Close BCU with the X when you are done.

## Do NOT uninstall
- GPU, chipset, audio or network drivers
- Microsoft Visual C++ Redistributables, .NET and DirectX runtimes
- Microsoft Edge WebView2 Runtime (many apps need it)
- Microsoft Edge itself (UDP removes it in a later step and keeps WebView2)
- Game anti-cheat services (Easy Anti-Cheat, BattlEye, Riot Vanguard, ...), or games stop launching

## Do I need to save?
No. Each uninstall happens right away and cannot be undone by UDP. The restore point created at the start is your safety net.

> Keep "Show system components" and "Show protected items" switched off in the filters on the left (they are off by default). You do not need BCU's startup manager: Autoruns comes later.
'@
}

function Get-UdpBcuPortable {
    param([hashtable]$Context, $Tool)

    $release = Get-UdpGitHubLatestRelease -Repo $Tool.githubRelease.repo
    $asset = Get-UdpGitHubAsset -Release $release -Pattern $Tool.githubRelease.assetPattern
    $expected = Get-UdpGitHubAssetSha256 -Asset $asset
    if (-not $expected) { throw "GitHub publishes no SHA256 digest for $($asset.name); the portable build cannot be verified." }

    $folder = New-UdpWorkFolder -Context $Context -Name 'bcu'
    $archive = Join-Path $folder $asset.name
    Invoke-UdpDownload -Uri $asset.browser_download_url -OutFile $archive | Out-Null
    if (-not (Test-UdpFileHash -Path $archive -ExpectedSha256 $expected)) {
        throw (New-Object System.Security.SecurityException('The BCU archive does not match the SHA256 digest published by GitHub; skipped for safety.'))
    }

    $extracted = Join-Path $folder 'extracted'
    New-Item -ItemType Directory -Path $extracted -Force | Out-Null
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    $code = Invoke-UdpProcess -FilePath $tar -ArgumentList @('-xf', $archive, '-C', $extracted) -Label 'tar'
    if ($code -ne 0) { throw "Extracting $($asset.name) failed (tar exit code $code)." }

    # The archive has one build per architecture plus a launcher at the top; start the matching build directly.
    $archFolder = 'win-x64'
    if ($Context.System.Architecture -eq 'arm64') { $archFolder = 'win-arm64' }
    foreach ($candidate in @((Join-Path $extracted "$archFolder\$($Tool.exeName)"), (Join-Path $extracted $Tool.exeName))) {
        if (Test-Path -LiteralPath $candidate) {
            Write-UdpLog "Using BCU $($release.tag_name) (portable)" -Level Info
            return $candidate
        }
    }
    $found = Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter $Tool.exeName | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "$($Tool.exeName) was not found in $($asset.name)."
}

function Get-UdpBcuInstalled {
    param([hashtable]$Context, $Tool, [switch]$RemoveAtEnd)

    $wasInstalled = Test-UdpWingetPackageInstalled -Id $Tool.winget
    $install = Install-UdpWingetPackage -Context $Context -Id $Tool.winget
    if (-not $install.Success) { throw "winget could not install BCU (exit code $($install.ExitCode))." }
    if ($Context.DryRun) { return $null }

    $location = Get-UdpInstallLocation -DisplayNamePattern $Tool.uninstallDisplayName
    $candidates = @()
    if ($location) { $candidates += (Join-Path $location $Tool.exeName) }
    $candidates += (Join-Path $env:ProgramFiles "BCUninstaller\$($Tool.exeName)")
    $candidates += (Join-Path ${env:ProgramFiles(x86)} "BCUninstaller\$($Tool.exeName)")

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            if ($RemoveAtEnd -and -not $wasInstalled) {
                Register-UdpCleanup -Description 'Uninstall Bulk Crap Uninstaller (installed for this run only)' -Data @{ Id = $Tool.winget } -Action {
                    param($Context, $Data)
                    Uninstall-UdpWingetPackage -Context $Context -Id $Data.Id | Out-Null
                }
            }
            return $candidate
        }
    }
    throw 'BCU was installed but BCUninstaller.exe was not found.'
}

function Invoke-UdpBcu {
    param([hashtable]$Context, [hashtable]$Options)

    $tool = Get-UdpToolConfig -Context $Context -Id 'bcu'

    try {
        if ($Options.Mode -eq 'Install') {
            $exe = Get-UdpBcuInstalled -Context $Context -Tool $tool
        }
        elseif ($Context.System.TarSupports7z) {
            $exe = Get-UdpBcuPortable -Context $Context -Tool $tool
        }
        else {
            Write-UdpLog 'The built-in tar.exe cannot extract .7z here (older Windows); using winget for this run instead.' -Level Warning
            if (-not (Get-UdpWingetPath)) {
                return New-UdpStepResult -Status Skipped -Message 'Neither the portable build (needs a newer tar.exe) nor winget is available.'
            }
            $exe = Get-UdpBcuInstalled -Context $Context -Tool $tool -RemoveAtEnd
        }
    }
    catch [System.Security.SecurityException] {
        return New-UdpStepResult -Status Skipped -Message $_.Exception.Message
    }

    if ($Context.DryRun) {
        Write-UdpLog '[dry run] would show the BCU guide, open BCU and wait until it is closed' -Level DryRun
        return New-UdpStepResult -Status Success -Message 'Dry run: BCU not opened.'
    }

    $answer = Request-UdpDecision -Context $Context -Kind 'Briefing' -Title 'Bulk Crap Uninstaller' -Body (Get-UdpBcuBriefing) -Buttons @(
        (New-UdpButton 'launch' 'Open Bulk Crap Uninstaller' -Primary),
        (New-UdpButton 'skip' 'Skip this step'))
    if ($answer -ne 'launch') { return New-UdpStepResult -Status Skipped -Message 'Skipped by you.' }

    Invoke-UdpInteractiveProcess -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -WaitForProcessName $tool.processName | Out-Null
    return New-UdpStepResult -Status Success -Message 'BCU was opened and closed.'
}
