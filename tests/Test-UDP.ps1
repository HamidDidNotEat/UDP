<#
.SYNOPSIS
    Offline and online self-checks for UDP. Changes nothing on the system.

.DESCRIPTION
    Always: parses every .ps1 file, checks that source files are plain ASCII (Windows PowerShell 5.1
    reads files without a BOM as ANSI), validates config/tools.json, loads every XAML page and
    runs small unit checks.
    -Online: also downloads the pinned Edge_Removal.bat and the latest Win11Debloat release to
    check that UDP still understands them.
    -DryRunSteps: also runs every step in dry-run mode without the window (needs administrator
    rights because Win11Debloat -WhatIf does).

    Run with Windows PowerShell 5.1:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File tests\Test-UDP.ps1 [-Online] [-DryRunSteps]
#>
param(
    [switch]$Online,
    [switch]$DryRunSteps
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.ArrayList

function Assert-Udp {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Host "  ok    $Message" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Message" -ForegroundColor Red; [void]$failures.Add($Message) }
}

Write-Host "UDP self-test ($($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion))" -ForegroundColor Cyan

# ------------------------------------------------------------------ syntax and encoding
Write-Host 'Syntax and encoding'
$sourceFiles = Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.bat', '*.xaml', '*.json', '*.yml' |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($root.Length + 1)
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    Assert-Udp ($nonAscii -eq 0) "$relative is ASCII"
    if ($file.Extension -eq '.ps1') {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert-Udp ($errors.Count -eq 0) "$relative parses ($(@($errors | ForEach-Object { $_.Message }) -join '; '))"
    }
    if ($file.Extension -eq '.bat') {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $lfOnly = ([regex]::Matches($text, "(?<!`r)`n")).Count
        Assert-Udp ($lfOnly -eq 0) "$relative uses CRLF line endings"
    }
}

# ------------------------------------------------------------------ load UDP
foreach ($folder in 'src\Core', 'src\Steps') {
    foreach ($file in (Get-ChildItem -Path (Join-Path $root $folder) -Filter '*.ps1' | Sort-Object Name)) { . $file.FullName }
}

$workDir = Join-Path $env:TEMP 'UDP-test'
$context = @{ Root = $root; DryRun = $true; WorkDir = $workDir; Sync = $null; Quiet = $true }
Set-UdpLogContext -Context $context
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

# ------------------------------------------------------------------ config
Write-Host 'config/tools.json'
$context.Config = Import-UdpConfig -Path (Join-Path $root 'config\tools.json')
Assert-Udp $true 'tools.json loads'
$entries = @($context.Config.tools.PSObject.Properties | Where-Object { $_.Name -ne 'browser' })
$entries += @($context.Config.tools.browser.browsers.PSObject.Properties)
foreach ($property in $entries) {
    $tool = $property.Value
    Assert-Udp ([bool]$tool.name -and [bool]$tool.homepage -and [bool]$tool.license) "$($property.Name): name, homepage and license are set"
}
foreach ($id in 'shutup10', 'autoruns') {
    Assert-Udp ([bool]$context.Config.tools.$id.integrity.expectedSigner) "$id has an expected signer"
}
foreach ($browser in $context.Config.tools.browser.browsers.PSObject.Properties) {
    Assert-Udp ([bool]$browser.Value.integrity.expectedSigner) "browser $($browser.Name) has an expected signer"
    Assert-Udp ([bool]$browser.Value.winget) "browser $($browser.Name) has a winget id"
}
Assert-Udp ($context.Config.tools.edgeRemoval.sha256 -match '^[0-9a-f]{64}$') 'Edge removal has a pinned SHA256'
$version = $context.Config.project.version
$changelog = [System.IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md'))
Assert-Udp ($changelog.Contains("## [$version]")) "CHANGELOG.md has a section for version $version"
$catalogIds = @(Get-UdpStepCatalog | ForEach-Object { $_.Id })
foreach ($step in Get-UdpStepCatalog) {
    foreach ($function in $step.Available, $step.Plan, $step.Invoke) {
        Assert-Udp ([bool](Get-Command $function -ErrorAction SilentlyContinue)) "$($step.Id): function $function exists"
    }
}
Assert-Udp (($catalogIds -join ',') -eq 'win11debloat,shutup10,bcu,browser,edge,nvcleanstall,autoruns') 'Steps are in the required order'

# ------------------------------------------------------------------ unit checks
Write-Host 'Helpers'
$sums = "aaaa  other.zip`n" + ('b' * 64) + "  Win11Debloat.zip`n"
Assert-Udp ((Get-UdpHashFromSums -SumsText $sums -FileName 'Win11Debloat.zip') -eq ('b' * 64)) 'Get-UdpHashFromSums finds the right line'
Assert-Udp ($null -eq (Get-UdpHashFromSums -SumsText $sums -FileName 'missing.zip')) 'Get-UdpHashFromSums returns null for a missing file'
Assert-Udp ((Format-UdpArgument 'C:\Program Files\x.cfg') -eq '"C:\Program Files\x.cfg"') 'Format-UdpArgument quotes paths with spaces'
Assert-Udp ((Format-UdpArgument '/quiet') -eq '/quiet') 'Format-UdpArgument leaves simple arguments alone'
Assert-Udp ((Get-UdpSubjectOrganization 'CN="Brave Software, Inc.", O="Brave Software, Inc.", L=San Francisco') -eq 'Brave Software, Inc.') 'Quoted O= is parsed'
Assert-Udp ((Get-UdpSubjectOrganization 'CN=Google LLC, O=Google LLC, L=Mountain View') -eq 'Google LLC') 'Plain O= is parsed'
$browsers = @(Get-UdpInstalledBrowsers)
Assert-Udp (@($browsers | Where-Object { $_ -is [array] }).Count -eq 0) "Get-UdpInstalledBrowsers returns a flat list ($($browsers -join ', '))"

$context.System = @{ Build = 26200; Architecture = 'x64'; Internet = $true; NvidiaGpu = $false; EdgeInstalled = $true; TarSupports7z = $true; InstalledBrowsers = @('Mozilla Firefox') }
$defaults = Get-UdpWin11DebloatArguments -Context $context -Options @{ Mode = 'Defaults' }
Assert-Udp (($defaults -contains '-RunDefaults') -and ($defaults -contains '-Silent') -and ($defaults -contains '-WhatIf')) 'Win11Debloat defaults: -Silent -RunDefaults (-WhatIf in dry run)'
$custom = Get-UdpWin11DebloatArguments -Context $context -Options @{ Mode = 'Custom'; Switches = @('DisableTelemetry', 'ForceRemoveEdge', 'Hide3dObjects') }
Assert-Udp ($custom -contains '-DisableTelemetry') 'Win11Debloat custom: chosen switch is passed'
Assert-Udp ($custom -notcontains '-ForceRemoveEdge') 'Win11Debloat custom: -ForceRemoveEdge is never passed'
Assert-Udp ($custom -notcontains '-Hide3dObjects') 'Win11Debloat custom: Windows 10-only option is dropped on Windows 11'

# ------------------------------------------------------------------ XAML
Write-Host 'XAML'
if ($PSVersionTable.PSEdition -eq 'Desktop' -and [System.Threading.Thread]::CurrentThread.ApartmentState -eq 'STA') {
    . (Join-Path $root 'src\UI\Wizard.ps1')
    Initialize-UdpApplication -Root $root
    foreach ($file in @(Get-Item (Join-Path $root 'ui\MainWindow.xaml')) + @(Get-ChildItem (Join-Path $root 'ui\Pages') -Filter '*.xaml')) {
        try { $null = Import-UdpXaml -Path $file.FullName; Assert-Udp $true "$($file.Name) loads" }
        catch { Assert-Udp $false "$($file.Name) loads: $($_.Exception.InnerException.Message) $($_.Exception.Message)" }
    }
}
else {
    Write-Host '  skip  XAML checks need Windows PowerShell 5.1 started with -STA' -ForegroundColor Yellow
}

# ------------------------------------------------------------------ online checks
if ($Online) {
    Write-Host 'Online'
    Initialize-UdpNetwork
    $edge = $context.Config.tools.edgeRemoval
    $file = Join-Path $workDir 'Edge_Removal.bat.txt'
    Invoke-UdpDownload -Uri $edge.url -OutFile $file | Out-Null
    Assert-Udp (Test-UdpFileHash -Path $file -ExpectedSha256 $edge.sha256) 'Edge_Removal.bat matches the pinned SHA256'
    $payload = Get-UdpEdgeRemovalPayload -ScriptText ([System.IO.File]::ReadAllText($file)) -Tool $edge -Options @{ RemoveWidgets = $false; RemoveXSocial = $false }
    Assert-Udp ($payload -match [regex]::Escape('$also_remove_webview = 0')) 'Edge payload keeps WebView2'
    Assert-Udp ($payload -match [regex]::Escape('$also_remove_widgets = 0') -and $payload -match [regex]::Escape('$also_remove_xsocial = 0')) 'Edge payload: widgets and xsocial off by default'
    Assert-Udp ($payload -notmatch '-verb runas') 'Edge payload does not contain the self-relaunch'
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($payload, [ref]$tokens, [ref]$errors)
    Assert-Udp ($errors.Count -eq 0) 'Edge payload is valid PowerShell'

    $tool = $context.Config.tools.win11debloat
    $release = Get-UdpGitHubLatestRelease -Repo $tool.githubRelease.repo
    $zip = Get-UdpGitHubAsset -Release $release -Name $tool.githubRelease.asset
    $zipPath = Join-Path $workDir $zip.name
    Invoke-UdpDownload -Uri $zip.browser_download_url -OutFile $zipPath | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath (Join-Path $workDir 'w11d') -Force
    $script = Get-ChildItem (Join-Path $workDir 'w11d') -Recurse -Filter $tool.entryScript | Select-Object -First 1
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    $known = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    foreach ($option in $tool.customOptions) {
        Assert-Udp ($known -contains $option.switch) "Win11Debloat $($release.tag_name) knows -$($option.switch)"
    }
    foreach ($argument in @($tool.baseArguments) + '-RunDefaults', '-LogPath') {
        Assert-Udp ($known -contains $argument.TrimStart('-')) "Win11Debloat $($release.tag_name) knows $argument"
    }
}

# ------------------------------------------------------------------ dry run of every step
if ($DryRunSteps) {
    Write-Host 'Dry run of all steps (no window)'
    $context.Remove('Quiet')
    $context.System = Get-UdpSystemInfo
    $context.LogDir = Join-Path $workDir 'logs'
    New-Item -ItemType Directory -Path $context.LogDir -Force | Out-Null
    $context.LogFile = Join-Path $context.LogDir 'dryrun.log'
    $context.Sync = New-UdpSync
    $context.Sync.AutoAnswer = $true
    $selection = @{
        win11debloat = @{ Enabled = $true; Mode = 'Defaults' }
        shutup10     = @{ Enabled = $true; Mode = 'Gui' }
        bcu          = @{ Enabled = $true; Mode = 'RunOnce' }
        browser      = @{ Enabled = $true; Browser = 'firefox'; Extensions = $true; ExtensionIds = @('uBlock0@raymondhill.net', 'jid1-MnnxcxisBPnSXQ@jetpack') }
        edge         = @{ Enabled = $true; RemoveWidgets = $false; RemoveXSocial = $false }
        nvcleanstall = @{ Enabled = $true }
        autoruns     = @{ Enabled = $true }
    }
    Invoke-UdpRun -Context $context -Selection $selection
    $item = $null
    while ($context.Sync.LogQueue.TryDequeue([ref]$item)) { Write-Host "    $($item.Text)" -ForegroundColor DarkGray }
    foreach ($result in $context.Sync.Results) {
        Assert-Udp ($result.Status -ne 'Failed') "dry run: $($result.Name) -> $($result.Status). $($result.Message)"
    }
}

Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) check(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
exit 0
