# Before/after report. UDP measures the PC when a run starts, then opens once more after the
# restart (a one-time scheduled task at the next sign-in), waits until Windows has settled,
# measures again and shows what changed. Reports are saved in %ProgramData%\UDP\reports.

$script:UdpReportTaskPath = '\UDP\'
$script:UdpReportTaskName = 'Before and after report'

# What the report compares. LowerIsBetter decides whether a change is shown as an improvement.
$script:UdpReportMetrics = @(
    @{ Key = 'Processes'; Label = 'Running processes'; LowerIsBetter = $true; Decimals = 0; Unit = '' }
    @{ Key = 'RamUsedGB'; Label = 'RAM in use'; LowerIsBetter = $true; Decimals = 1; Unit = ' GB' }
    @{ Key = 'ServicesRunning'; Label = 'Running services'; LowerIsBetter = $true; Decimals = 0; Unit = '' }
    @{ Key = 'StartupEntries'; Label = 'Startup entries (Run keys and Startup folders)'; LowerIsBetter = $true; Decimals = 0; Unit = '' }
    @{ Key = 'DesktopPrograms'; Label = 'Desktop programs installed'; LowerIsBetter = $true; Decimals = 0; Unit = '' }
    @{ Key = 'StoreApps'; Label = 'Store apps installed'; LowerIsBetter = $true; Decimals = 0; Unit = '' }
    @{ Key = 'FreeDiskGB'; Label = 'Free space on the system drive'; LowerIsBetter = $false; Decimals = 1; Unit = ' GB' }
)

function Get-UdpStartupEntryCount {
    $count = 0
    $skip = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
        $values = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($values) { $count += @($values.PSObject.Properties | Where-Object { $skip -notcontains $_.Name }).Count }
    }
    foreach ($folder in [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup')) {
        if ($folder) { $count += @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count }
    }
    return $count
}

function Get-UdpDesktopProgramCount {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    # Programs as Settings > Apps lists them: named entries that are not hidden components or updates.
    $names = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName -and -not $_.ReleaseType } |
            ForEach-Object { $_.DisplayName } | Sort-Object -Unique)
    return $names.Count
}

function Get-UdpStoreAppCount {
    # Apps from the Store (not frameworks or Windows system components), for all users when allowed.
    try { $packages = @(Get-AppxPackage -AllUsers -PackageTypeFilter Main -ErrorAction Stop) }
    catch { $packages = @(Get-AppxPackage -PackageTypeFilter Main -ErrorAction SilentlyContinue) }
    return @($packages | Where-Object { -not $_.IsFramework -and [string]$_.SignatureKind -eq 'Store' } | ForEach-Object { $_.Name } | Sort-Object -Unique).Count
}

function Get-UdpSnapshot {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
    return [ordered]@{
        Taken           = (Get-Date).ToString('s')
        UptimeMinutes   = [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes
        Processes       = @(Get-Process).Count
        RamUsedGB       = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        ServicesRunning = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count
        StartupEntries  = Get-UdpStartupEntryCount
        DesktopPrograms = Get-UdpDesktopProgramCount
        StoreApps       = Get-UdpStoreAppCount
        FreeDiskGB      = [math]::Round([double]$drive.FreeSpace / 1GB, 2)
    }
}

# "5 November 2026, 19:30" whatever the Windows display language (UDP's text is English).
function Format-UdpDate {
    param($Date)
    return ([datetime]$Date).ToString('d MMMM yyyy, HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}

# "-30 (-19%)", "+1.2 GB (+3%)" or "no change".
function Format-UdpReportChange {
    param([double]$Before, [double]$After, [int]$Decimals, [string]$Unit)
    $difference = [math]::Round($After - $Before, $Decimals)
    if ($difference -eq 0) { return 'no change' }
    $number = $difference.ToString("N$Decimals", [System.Globalization.CultureInfo]::InvariantCulture)
    if ($difference -gt 0) { $number = "+$number" }
    $text = "$number$Unit"
    if ($Before -ne 0) {
        $percent = [math]::Round(100 * $difference / $Before)
        if ($percent -ne 0) {
            $sign = ''
            if ($percent -gt 0) { $sign = '+' }
            $text += " ($sign$percent%)"
        }
    }
    return $text
}

function Format-UdpReportValue {
    param($Value, [int]$Decimals, [string]$Unit)
    return (([double]$Value).ToString("N$Decimals", [System.Globalization.CultureInfo]::InvariantCulture) + $Unit)
}

# One row per metric: Label, Before, After, Change, and whether it improved.
function Get-UdpReportRows {
    param($Before, $After)
    $rows = @()
    foreach ($metric in $script:UdpReportMetrics) {
        $b = [double]$Before.($metric.Key)
        $a = [double]$After.($metric.Key)
        $better = $null
        if ([math]::Round($a - $b, $metric.Decimals) -ne 0) { $better = (($a -lt $b) -eq $metric.LowerIsBetter) }
        $rows += [pscustomobject]@{
            Label  = $metric.Label
            Before = Format-UdpReportValue -Value $b -Decimals $metric.Decimals -Unit $metric.Unit
            After  = Format-UdpReportValue -Value $a -Decimals $metric.Decimals -Unit $metric.Unit
            Change = Format-UdpReportChange -Before $b -After $a -Decimals $metric.Decimals -Unit $metric.Unit
            Better = $better
        }
    }
    return $rows
}

# Remembers this run (date, version, step results and the "before" snapshot) in state.json.
function Save-UdpLastRun {
    param([hashtable]$Context, $Before, [object[]]$Results, [bool]$ReportPending)
    $state = Get-UdpState
    $state.LastRun = [ordered]@{
        date          = (Get-Date).ToString('s')
        version       = $Context.Config.project.version
        logFile       = $Context.LogFile
        results       = @($Results | ForEach-Object { [ordered]@{ name = $_.Name; status = $_.Status } })
        before        = $Before
        after         = $null
        reportPending = $ReportPending
        reportFile    = $null
    }
    Save-UdpState -State $state
}

# Keeps a copy of UDP in %ProgramData%\UDP\app for the run after the restart: the one-liner deletes
# its own copy when UDP closes.
function Copy-UdpAppForReport {
    param([hashtable]$Context)
    $target = Join-Path $env:ProgramData 'UDP\app'
    if ((Resolve-Path -LiteralPath $Context.Root).Path.TrimEnd('\') -eq $target) { return $target }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($item in 'UDP.ps1', 'src', 'ui', 'config') {
        Copy-Item -LiteralPath (Join-Path $Context.Root $item) -Destination $target -Recurse -Force
    }
    return $target
}

# One-time task: at the next sign-in of the user who ran UDP, with administrator rights and no
# prompt. UDP removes the task as soon as it starts.
function Register-UdpReportTask {
    param([hashtable]$Context)
    $app = Copy-UdpAppForReport -Context $Context
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$(Join-Path $app 'UDP.ps1')`" -Report"

    $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $trigger.Delay = 'PT1M'
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskPath $script:UdpReportTaskPath -TaskName $script:UdpReportTaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Description 'Ultimate Debloat Pack: shows the before/after report once after the restart, then removes itself.' -Force | Out-Null
    Write-UdpLog "Scheduled the before/after report for the next sign-in of $user (task $($script:UdpReportTaskPath)$($script:UdpReportTaskName))." -Level Info
}

function Unregister-UdpReportTask {
    $task = Get-ScheduledTask -TaskPath $script:UdpReportTaskPath -TaskName $script:UdpReportTaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskPath $script:UdpReportTaskPath -TaskName $script:UdpReportTaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-UdpLog 'Removed the one-time report task.' -Level Info
    }
}

# Saves the finished report (JSON for UDP, text for people) and marks it done in state.json.
function Save-UdpReport {
    param($LastRun, $After)
    $folder = Join-Path $env:ProgramData 'UDP\reports'
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $json = Join-Path $folder "report_$stamp.json"
    $text = Join-Path $folder "report_$stamp.txt"

    $document = [ordered]@{ run = $LastRun.date; version = $LastRun.version; before = $LastRun.before; after = $After }
    [System.IO.File]::WriteAllText($json, (ConvertTo-Json -InputObject $document -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

    $lines = @("Ultimate Debloat Pack - before/after report", "Run: $($LastRun.date) (UDP $($LastRun.version))", '')
    foreach ($row in (Get-UdpReportRows -Before $LastRun.before -After $After)) {
        $lines += ('{0,-48} {1,12} -> {2,12}   {3}' -f $row.Label, $row.Before, $row.After, $row.Change)
    }
    [System.IO.File]::WriteAllText($text, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

    $state = Get-UdpState
    if ($state.LastRun) {
        $state.LastRun.after = $After
        $state.LastRun.reportPending = $false
        $state.LastRun.reportFile = $json
        Save-UdpState -State $state
    }
    Write-UdpLog "Report saved: $text" -Level Info
    return $json
}
