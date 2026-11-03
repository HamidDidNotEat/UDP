# winget wrappers. winget verifies the installer hash from its manifest before installing.
# Return codes from https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md

$script:WingetCodes = @{
    NoPackagesFound         = -1978335212  # 0x8A150014
    UpdateNotApplicable     = -1978335189  # 0x8A15002B
    PackageAlreadyInstalled = -1978335135  # 0x8A150061
    RebootRequiredToFinish  = -1978334967  # 0x8A150109
    InstallAlreadyInstalled = -1978334963  # 0x8A15010D
}

function Get-UdpWingetPath {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) { return $winget.Source }
    return $null
}

function Test-UdpWingetPackageInstalled {
    param([Parameter(Mandatory)][string]$Id)

    $winget = Get-UdpWingetPath
    if (-not $winget) { return $false }
    $null = & $winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>$null
    return ($LASTEXITCODE -eq 0)
}

# Installs a package. Returns an object with Success, AlreadyInstalled, RebootRequired and ExitCode.
function Install-UdpWingetPackage {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Id
    )

    $winget = Get-UdpWingetPath
    if (-not $winget) {
        Write-UdpLog 'winget is not available.' -Level Warning
        return [pscustomobject]@{ Success = $false; AlreadyInstalled = $false; RebootRequired = $false; ExitCode = $null }
    }

    $arguments = @('install', '--id', $Id, '--exact', '--source', 'winget', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')

    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would run: winget $($arguments -join ' ')" -Level DryRun
        return [pscustomobject]@{ Success = $true; AlreadyInstalled = $false; RebootRequired = $false; ExitCode = 0 }
    }

    $code = Invoke-UdpProcess -FilePath $winget -ArgumentList $arguments -Label "winget install $Id"
    $already = ($code -eq $script:WingetCodes.PackageAlreadyInstalled -or
        $code -eq $script:WingetCodes.UpdateNotApplicable -or
        $code -eq $script:WingetCodes.InstallAlreadyInstalled)
    $reboot = ($code -eq $script:WingetCodes.RebootRequiredToFinish)

    return [pscustomobject]@{
        Success          = ($code -eq 0 -or $already -or $reboot)
        AlreadyInstalled = $already
        RebootRequired   = $reboot
        ExitCode         = $code
    }
}

function Uninstall-UdpWingetPackage {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Id
    )

    $winget = Get-UdpWingetPath
    if (-not $winget) { return $false }

    $arguments = @('uninstall', '--id', $Id, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity')
    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would run: winget $($arguments -join ' ')" -Level DryRun
        return $true
    }
    $code = Invoke-UdpProcess -FilePath $winget -ArgumentList $arguments -Label "winget uninstall $Id"
    return ($code -eq 0)
}

# Folder where winget unpacks portable packages (machine or user scope).
function Find-UdpWingetPortableFile {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Filter
    )
    $roots = @(
        (Join-Path $env:ProgramFiles 'WinGet\Packages'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages')
    )
    foreach ($root in $roots) {
        foreach ($folder in (Get-ChildItem -Path $root -Directory -Filter "$Id*" -ErrorAction SilentlyContinue)) {
            $files = @(Get-ChildItem -Path $folder.FullName -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue)
            if ($files.Count -gt 0) { return $files }
        }
    }
    return @()
}

# Install folder of a classic program, read from its uninstall entry.
function Get-UdpInstallLocation {
    param([Parameter(Mandatory)][string]$DisplayNamePattern)
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        $entry = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $DisplayNamePattern -and $_.InstallLocation } |
            Select-Object -First 1
        if ($entry) { return $entry.InstallLocation.Trim('"') }
    }
    return $null
}
