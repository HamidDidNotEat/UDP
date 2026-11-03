<#
.SYNOPSIS
    UDP (Ultimate Debloat Pack): one wizard that runs Win11Debloat, O&O ShutUp10++, Bulk Crap
    Uninstaller, an alternative browser, Edge removal, NVCleanstall and Autoruns, one after another.

.DESCRIPTION
    Every tool is downloaded at run time from its official source (listed in config\tools.json)
    and verified (Authenticode signature or published SHA256) before it runs.
    Requires Windows PowerShell 5.1 and administrator rights; UDP re-launches itself if needed.

.PARAMETER DryRun
    Show what would happen without changing anything (can also be ticked on the welcome page).

.PARAMETER RevertBrowserPolicies
    Remove the browser extension policies UDP created, then exit. No wizard is shown.

.EXAMPLE
    .\UDP.ps1
.EXAMPLE
    .\UDP.ps1 -DryRun
.EXAMPLE
    .\UDP.ps1 -RevertBrowserPolicies
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RevertBrowserPolicies
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$UdpScript = $PSCommandPath
$UdpRoot = $PSScriptRoot
$WindowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Show-UdpStartupError {
    param([string]$Message)
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, 'UDP', 'OK', 'Error') | Out-Null
    }
    catch {
        Write-Host $Message -ForegroundColor Red
    }
}

# ---------------------------------------------------------------- 1. Right host, elevated
# WPF needs an STA thread, and Checkpoint-Computer / the Appx cmdlets used by Win11Debloat only
# exist in Windows PowerShell 5.1, so UDP always runs in powershell.exe 5.1 as administrator.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$isDesktop = ($PSVersionTable.PSEdition -ne 'Core' -and $PSVersionTable.PSVersion.Major -eq 5)
$isSta = ([System.Threading.Thread]::CurrentThread.ApartmentState -eq 'STA')

if (-not ($isAdmin -and $isDesktop -and $isSta)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA')
    # The wizard has its own window, so the console is hidden. The revert action has no window:
    # keep its console open so the result can be read.
    if ($RevertBrowserPolicies) { $arguments += '-NoExit' } else { $arguments += @('-WindowStyle', 'Hidden') }
    $arguments += @('-File', "`"$UdpScript`"")
    if ($DryRun) { $arguments += '-DryRun' }
    if ($RevertBrowserPolicies) { $arguments += '-RevertBrowserPolicies' }
    try {
        Start-Process -FilePath $WindowsPowerShell -ArgumentList ($arguments -join ' ') -Verb RunAs -ErrorAction Stop
    }
    catch {
        Show-UdpStartupError "UDP needs administrator rights to run.`r`n`r`n$($_.Exception.Message)"
        exit 1
    }
    exit 0
}

# ---------------------------------------------------------------- 2. Load UDP
foreach ($folder in 'src\Core', 'src\Steps', 'src\UI') {
    foreach ($file in (Get-ChildItem -Path (Join-Path $UdpRoot $folder) -Filter '*.ps1' | Sort-Object Name)) {
        . $file.FullName
    }
}

$context = @{
    Root    = $UdpRoot
    DryRun  = [bool]$DryRun
    WorkDir = Join-Path $env:TEMP 'UDP\work'
    Sync    = $null
    Config  = $null
    System  = $null
}

try {
    Initialize-UdpLog -Context $context
    Initialize-UdpNetwork
    $context.Config = Import-UdpConfig -Path (Join-Path $UdpRoot 'config\tools.json')
    Write-UdpLog "UDP $($context.Config.project.version) started from $UdpRoot" -Level Step

    if ($RevertBrowserPolicies) {
        Remove-UdpBrowserPolicies -Context $context | Out-Null
        Write-UdpLog "Log file: $($context.LogFile)" -Level Info
        exit 0
    }

    # From here on, log lines go to the window's log panel (and to the log file).
    $context.Sync = New-UdpSync
    if (-not (Test-Path -LiteralPath $context.WorkDir)) { New-Item -ItemType Directory -Path $context.WorkDir -Force | Out-Null }

    Write-UdpLog 'Checking this PC' -Level Info
    $context.System = Get-UdpSystemInfo
    foreach ($line in ((Format-UdpSystemInfo -System $context.System) -split "`r`n")) { Write-UdpLog $line -Level Detail }

    Show-UdpWizard -Context $context
}
catch {
    $message = "UDP stopped because of an unexpected error:`r`n`r`n$($_.Exception.Message)"
    if ($context.LogFile) {
        Write-UdpLog ($_ | Out-String).Trim() -Level Error
        $message += "`r`n`r`nLog file: $($context.LogFile)"
    }
    Show-UdpStartupError $message
    exit 1
}
finally {
    if ($context.WorkDir -and (Test-Path -LiteralPath $context.WorkDir)) {
        Remove-Item -LiteralPath $context.WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
