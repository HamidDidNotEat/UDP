# System checks that run before the wizard opens: admin rights, Windows version, PowerShell,
# internet, winget, GPU and installed browsers. Nothing here changes the system.

function Test-UdpIsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-UdpInternet {
    foreach ($uri in 'https://api.github.com', 'https://www.microsoft.com') {
        try {
            $null = Invoke-WebRequest -Uri $uri -Method Head -UseBasicParsing -TimeoutSec 10 -UserAgent 'UDP' -ErrorAction Stop
            return $true
        }
        catch {
            # A HEAD request can be refused (405) while the connection itself works.
            if ($_.Exception.Response) { return $true }
        }
    }
    return $false
}

function Get-UdpWingetVersion {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { return $null }
    try {
        # Collect all output before taking the first line: stopping the pipeline early would
        # end winget and turn its exit code into -1.
        $output = @(& $winget.Source --version 2>$null)
        if ($LASTEXITCODE -eq 0 -and $output.Count -gt 0) { return ([string]$output[0]).Trim() }
    }
    catch { }
    return $null
}

# Browsers register themselves under StartMenuInternet. Edge and Internet Explorer are not counted
# as an alternative browser.
function Get-UdpInstalledBrowsers {
    $roots = @(
        'HKLM:\SOFTWARE\Clients\StartMenuInternet',
        'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet',
        'HKCU:\SOFTWARE\Clients\StartMenuInternet'
    )
    $names = @()
    foreach ($root in $roots) {
        foreach ($key in (Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            if ($key.PSChildName -match '^(Microsoft Edge|IEXPLORE\.EXE)') { continue }
            $display = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).'(default)'
            if (-not $display) { $display = $key.PSChildName }
            if ($names -notcontains $display) { $names += $display }
        }
    }
    # Callers wrap the result in @() so that zero or one browser still gives an array.
    return $names
}

# Paths of msedge.exe that still exist.
function Get-UdpEdgeExePaths {
    $paths = @()
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $base) { continue }
        $path = Join-Path $base 'Microsoft\Edge\Application\msedge.exe'
        if ((Test-Path -LiteralPath $path) -and $paths -notcontains $path) { $paths += $path }
    }
    return $paths
}

# Edge's own entry in Settings > Apps (not "Microsoft Edge WebView2 Runtime" or "Microsoft Edge Update").
function Test-UdpEdgeUninstallEntry {
    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        $entry = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'Microsoft Edge' }
        if ($entry) { return $true }
    }
    return $false
}

# Edge counts as installed while its uninstall entry or msedge.exe is still there.
function Test-UdpEdgeInstalled {
    return ((Test-UdpEdgeUninstallEntry) -or (@(Get-UdpEdgeExePaths).Count -gt 0))
}

function Test-UdpWebView2Installed {
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($base -and (Test-Path -LiteralPath (Join-Path $base 'Microsoft\EdgeWebView\Application'))) {
            return $true
        }
    }
    return $false
}

# Windows 11 ships a tar.exe built with liblzma, which can extract .7z archives.
# The older tar.exe in Windows 10 may not, so BCU's "Run once" mode falls back to winget there.
function Test-UdpTarSupports7z {
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tar)) { return $false }
    try {
        $version = (& $tar --version 2>$null) -join ' '
        return ($version -match 'liblzma')
    }
    catch {
        return $false
    }
}

function Get-UdpArchitecture {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpu -and $cpu.Architecture -eq 12) { return 'arm64' }
    if ([Environment]::Is64BitOperatingSystem) { return 'x64' }
    return 'x86'
}

function Get-UdpSystemInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue

    $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue)
    $nvidia = @($gpus | Where-Object { $_.Name -match 'NVIDIA' -or $_.AdapterCompatibility -match 'NVIDIA' })

    $wingetVersion = Get-UdpWingetVersion

    return @{
        OSCaption         = $os.Caption
        Build             = $build
        UBR               = $currentVersion.UBR
        DisplayVersion    = $currentVersion.DisplayVersion
        IsWindows11       = ($build -ge 22000)
        IsSupportedOS     = ($build -ge 10240)
        Architecture      = Get-UdpArchitecture
        PSVersion         = $PSVersionTable.PSVersion.ToString()
        PSEdition         = $PSVersionTable.PSEdition
        IsAdmin           = Test-UdpIsAdmin
        Internet          = Test-UdpInternet
        Winget            = [bool]$wingetVersion
        WingetVersion     = $wingetVersion
        GpuNames          = @($gpus | ForEach-Object { $_.Name })
        NvidiaGpu         = ($nvidia.Count -gt 0)
        InstalledBrowsers = @(Get-UdpInstalledBrowsers)
        EdgeInstalled     = Test-UdpEdgeInstalled
        WebView2Installed = Test-UdpWebView2Installed
        TarSupports7z     = Test-UdpTarSupports7z
    }
}

# Short, readable summary for the welcome page and the log.
function Format-UdpSystemInfo {
    param([Parameter(Mandatory)][hashtable]$System)

    $windows = '{0} (build {1}.{2})' -f $System.OSCaption, $System.Build, $System.UBR
    if ($System.DisplayVersion) { $windows = '{0}, version {1}' -f $windows, $System.DisplayVersion }

    $browsers = 'none found'
    if ($System.InstalledBrowsers.Count -gt 0) { $browsers = $System.InstalledBrowsers -join ', ' }

    $winget = 'not found (winget-based options will use direct downloads where possible)'
    if ($System.Winget) { $winget = $System.WingetVersion }

    $gpu = 'none detected'
    if ($System.GpuNames.Count -gt 0) { $gpu = $System.GpuNames -join ', ' }

    $lines = @(
        "Windows:            $windows",
        "Architecture:       $($System.Architecture)",
        "PowerShell:         $($System.PSVersion) ($($System.PSEdition))",
        "Administrator:      $(if ($System.IsAdmin) { 'yes' } else { 'NO' })",
        "Internet:           $(if ($System.Internet) { 'connected' } else { 'NOT CONNECTED' })",
        "winget:             $winget",
        "Graphics:           $gpu",
        "Other browsers:     $browsers",
        "Microsoft Edge:     $(if ($System.EdgeInstalled) { 'installed' } else { 'not installed' })",
        "WebView2 Runtime:   $(if ($System.WebView2Installed) { 'installed' } else { 'not found' })"
    )
    return ($lines -join "`r`n")
}
