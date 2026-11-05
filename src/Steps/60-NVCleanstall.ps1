# Step 6: NVCleanstall by TechPowerUp. Only offered when an NVIDIA GPU is detected.
# Installed with winget. If winget fails, UDP opens the official download page, lets you pick the
# installer you downloaded and checks that it is signed by TechPowerUp before running it.

function Test-UdpNVCleanstallAvailable {
    param([hashtable]$Context)
    if (-not $Context.System.NvidiaGpu) { return New-UdpAvailability $false 'No NVIDIA graphics card detected.' }
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    return New-UdpAvailability $true
}

function Get-UdpNVCleanstallPlan {
    param([hashtable]$Context, [hashtable]$Options)
    return @(
        'Install NVCleanstall with winget (TechPowerUp.NVCleanstall)',
        'Show a short guide, then open NVCleanstall and wait until you close it'
    )
}

function Get-UdpNVCleanstallBriefing {
    return @'
## What you will see
A wizard that downloads the official NVIDIA driver and builds a lighter installer with only the parts you choose. The exact labels can differ slightly between versions.

## Step by step
1. On the first page, choose to install the best driver for your hardware, then click Next.
2. Components: keep "Display Driver" (always needed). Add PhysX, and HD Audio only if your sound goes through HDMI or DisplayPort (TV or monitor speakers). Click Next.
3. Tweaks: tick "Disable Installer Telemetry & Advertising" and "Perform a Clean Installation". Click Next.
4. NVCleanstall downloads the driver and builds the installer, which takes a few minutes. Then click Install and follow the NVIDIA installer.
5. The screen may go black for a moment during the installation. That is normal.
6. When the installation has finished, close NVCleanstall with the X.

## Trade-off
Without the NVIDIA App you lose DLSS Override, ShadowPlay (Instant Replay and recording) and Smooth Motion. Alternatives: NVIDIA Profile Inspector for per-game driver settings, OBS Studio for recording.

> UDP continues automatically when you close NVCleanstall. It stays installed so you can use it for the next driver update.
'@
}

function Find-UdpNVCleanstallExe {
    param($Tool)
    $candidates = @()
    $location = Get-UdpInstallLocation -DisplayNamePattern $Tool.uninstallDisplayName
    if ($location) { $candidates += (Join-Path $location $Tool.exeName) }
    $candidates += (Join-Path $env:ProgramFiles "NVCleanstall\$($Tool.exeName)")
    $candidates += (Join-Path ${env:ProgramFiles(x86)} "NVCleanstall\$($Tool.exeName)")
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

# Fallback when winget is missing or fails: the user downloads the installer from TechPowerUp.
function Install-UdpNVCleanstallManually {
    param([hashtable]$Context, $Tool)

    $answer = Request-UdpDecision -Context $Context -Kind 'Confirm' -Title 'Download NVCleanstall manually' -Body (
        "winget could not install NVCleanstall.`r`n`r`n" +
        "UDP can open the official TechPowerUp download page. Download the installer there, then come back and select the downloaded file. " +
        'UDP checks that it is signed by TechPowerUp before running it.') -Buttons @(
        (New-UdpButton 'open' 'Open the download page' -Primary),
        (New-UdpButton 'skip' 'Skip NVCleanstall'))
    if ($answer -ne 'open') { return $false }

    Start-Process $Tool.downloadPage
    $file = Request-UdpDecision -Context $Context -Kind 'PickFile' -Title 'Select the NVCleanstall installer' -Body 'Select the NVCleanstall installer you just downloaded.' -FileFilter 'NVCleanstall installer|NVCleanstall*.exe|Programs|*.exe'
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $false }

    $check = Test-UdpSignature -Path $file -ExpectedSigner $Tool.integrity.expectedSigner
    if (-not $check.Valid) {
        throw (New-Object System.Security.SecurityException("The selected file failed the signature check ($($check.Reason)); it was not run."))
    }
    Invoke-UdpInteractiveProcess -FilePath $file | Out-Null
    return $true
}

function Invoke-UdpNVCleanstall {
    param([hashtable]$Context, [hashtable]$Options)

    $tool = Get-UdpToolConfig -Context $Context -Id 'nvcleanstall'

    if ($Context.DryRun) {
        Install-UdpWingetPackage -Context $Context -Id $tool.winget | Out-Null
        Write-UdpLog '[dry run] would show the NVCleanstall guide, open NVCleanstall and wait until it is closed' -Level DryRun
        return New-UdpStepResult -Status Success -Message 'Dry run: NVCleanstall not installed or opened.'
    }

    $exe = Find-UdpNVCleanstallExe -Tool $tool
    if ($exe) {
        Write-UdpLog 'NVCleanstall is already installed.' -Level Info
    }
    else {
        $install = Install-UdpWingetPackage -Context $Context -Id $tool.winget
        $exe = Find-UdpNVCleanstallExe -Tool $tool
        if (-not $install.Success -or -not $exe) {
            try {
                if (-not (Install-UdpNVCleanstallManually -Context $Context -Tool $tool)) {
                    return New-UdpStepResult -Status Skipped -Message 'NVCleanstall could not be installed with winget and the manual download was skipped.'
                }
            }
            catch [System.Security.SecurityException] {
                return New-UdpStepResult -Status Skipped -Message $_.Exception.Message
            }
            $exe = Find-UdpNVCleanstallExe -Tool $tool
            if (-not $exe) { return New-UdpStepResult -Status Failed -Message 'NVCleanstall.exe was not found after installation.' }
        }
    }

    $answer = Request-UdpDecision -Context $Context -Kind 'Briefing' -Title 'NVCleanstall' -Body (Get-UdpNVCleanstallBriefing) -Buttons @(
        (New-UdpButton 'launch' 'Open NVCleanstall' -Primary),
        (New-UdpButton 'skip' 'Skip this step'))
    if ($answer -ne 'launch') { return New-UdpStepResult -Status Skipped -Message 'Skipped by you. NVCleanstall stays installed for later driver updates.' }

    Invoke-UdpInteractiveProcess -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -WaitForProcessName $tool.processName | Out-Null
    return New-UdpStepResult -Status Success -Message 'NVCleanstall was opened and closed. It stays installed so you can use it for future driver updates.'
}
