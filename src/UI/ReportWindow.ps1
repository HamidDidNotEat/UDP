# The "What changed" window. After the restart (UDP.ps1 -Report) it first waits until Windows has
# settled, then measures the PC and compares it with the measurement taken when the run started.
# From the welcome page it shows a saved report.

$script:UdpReport = $null

function New-UdpReportWindow {
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)]$LastRun)

    $window = Import-UdpXaml -Path (Join-Path $Context.Root 'ui\Report.xaml')
    $controls = @{}
    foreach ($name in 'Logo', 'Subtitle', 'WaitPanel', 'WaitText', 'TableCard', 'Table', 'Notes', 'OpenFolderButton', 'CloseButton') {
        $controls[$name] = $window.FindName($name)
    }

    $logoPath = Join-Path $Context.Root 'ui\logo.png'
    if (Test-Path -LiteralPath $logoPath) {
        $logo = New-Object System.Windows.Media.Imaging.BitmapImage
        $logo.BeginInit()
        $logo.UriSource = New-Object System.Uri($logoPath)
        $logo.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $logo.EndInit()
        $window.Icon = $logo
        $controls.Logo.Source = $logo
    }

    $controls.Subtitle.Text = "Run of $(Format-UdpDate $LastRun.date) with UDP $($LastRun.version)"
    $controls.OpenFolderButton.Add_Click({
            $folder = Join-Path $env:ProgramData 'UDP\reports'
            if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
            Start-Process -FilePath explorer.exe -ArgumentList "`"$folder`""
        })
    $controls.CloseButton.Add_Click({ $script:UdpReport.Window.Close() })

    $script:UdpReport = @{ Context = $Context; LastRun = $LastRun; Window = $window; Controls = $controls; Started = (Get-Date); Calm = 0; Timer = $null }
    return $window
}

function Show-UdpReportTable {
    param($Before, $After)
    $c = $script:UdpReport.Controls
    $c.WaitPanel.Visibility = 'Collapsed'
    $c.TableCard.Visibility = 'Visible'

    $grid = $c.Table
    $grid.Children.Clear()
    $grid.RowDefinitions.Clear()
    $grid.ColumnDefinitions.Clear()
    foreach ($star in $true, $false, $false, $false) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        if ($star) { $column.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        else { $column.Width = [System.Windows.GridLength]::Auto }
        [void]$grid.ColumnDefinitions.Add($column)
    }

    $addCell = {
        param([string]$Text, [int]$Row, [int]$Column, [bool]$Header, [string]$Color)
        $block = New-Object System.Windows.Controls.TextBlock
        $block.Text = $Text
        $block.FontSize = 13
        $block.Margin = New-Object System.Windows.Thickness(0, 5, 18, 5)
        $block.TextWrapping = 'Wrap'
        if ($Column -gt 0) { $block.HorizontalAlignment = 'Right' }
        if ($Header) { $block.FontWeight = 'SemiBold'; $block.Foreground = New-UdpBrush '#6B7280' }
        elseif ($Color) { $block.Foreground = New-UdpBrush $Color }
        else { $block.Foreground = New-UdpBrush '#1F2937' }
        [System.Windows.Controls.Grid]::SetRow($block, $Row)
        [System.Windows.Controls.Grid]::SetColumn($block, $Column)
        [void]$grid.Children.Add($block)
    }

    $rows = @(Get-UdpReportRows -Before $Before -After $After)
    for ($i = 0; $i -le $rows.Count; $i++) { [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition)) }
    & $addCell 'What' 0 0 $true ''
    & $addCell 'Before' 0 1 $true ''
    & $addCell 'After' 0 2 $true ''
    & $addCell 'Change' 0 3 $true ''
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $color = '#6B7280'
        if ($row.Better -eq $true) { $color = '#15803D' }
        elseif ($row.Better -eq $false) { $color = '#B45309' }
        & $addCell $row.Label ($i + 1) 0 $false ''
        & $addCell $row.Before ($i + 1) 1 $false ''
        & $addCell $row.After ($i + 1) 2 $false ''
        & $addCell $row.Change ($i + 1) 3 $false $color
    }

    $c.Notes.Text = "Before: measured when UDP started, $($Before.UptimeMinutes) min after the PC was switched on. " +
    "After: measured $($After.UptimeMinutes) min after the restart, once Windows had settled. " +
    'The counts are exact. RAM in use depends on what is open and how long the PC has been on, so treat it as an estimate. ' +
    'The report is saved in C:\ProgramData\UDP\reports.'
}

# Called every 5 seconds while waiting: measure once Windows has been up for 4 minutes and the
# processor has been calm (below 25%) for 15 seconds, or after 10 minutes in any case.
function Update-UdpReportWait {
    $r = $script:UdpReport
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $uptime = ((Get-Date) - $os.LastBootUpTime).TotalMinutes
    $cpu = [int](Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if ($uptime -ge 4 -and $cpu -lt 25) { $r.Calm++ } else { $r.Calm = 0 }
    $waited = ((Get-Date) - $r.Started).TotalMinutes
    $r.Controls.WaitText.Text = "Waiting for Windows to settle before measuring (processor at $cpu%, PC on for $([int]$uptime) min). This takes a few minutes at most."

    if ($r.Calm -ge 3 -or $waited -ge 10) {
        $r.Timer.Stop()
        $r.Controls.WaitText.Text = 'Measuring this PC...'
        $r.Window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
        try {
            $after = Get-UdpSnapshot
            Save-UdpReport -LastRun $r.LastRun -After $after | Out-Null
            Show-UdpReportTable -Before $r.LastRun.before -After $after
        }
        catch {
            $r.Controls.WaitText.Text = "The measurement failed: $($_.Exception.Message)"
            Write-UdpLog "Report measurement failed: $($_.Exception.Message)" -Level Error
        }
    }
}

# -Measure: wait, measure and save (after the restart). Otherwise: show the saved report.
function Show-UdpReportWindow {
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)]$LastRun, [switch]$Measure, $Owner)

    $window = New-UdpReportWindow -Context $Context -LastRun $LastRun
    if ($Owner) {
        $window.Owner = $Owner
        $window.WindowStartupLocation = 'CenterOwner'
    }

    if ($Measure) {
        $script:UdpReport.Controls.WaitText.Text = 'Waiting for Windows to settle before measuring...'
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(5)
        $timer.Add_Tick({ Update-UdpReportWait })
        $script:UdpReport.Timer = $timer
        $timer.Start()
    }
    else {
        $before = $LastRun.before
        $after = $LastRun.after
        if ($LastRun.reportFile -and (Test-Path -LiteralPath $LastRun.reportFile)) {
            $saved = [System.IO.File]::ReadAllText($LastRun.reportFile) | ConvertFrom-Json
            $before = $saved.before
            $after = $saved.after
        }
        if ($before -and $after) { Show-UdpReportTable -Before $before -After $after }
        else { $script:UdpReport.Controls.WaitText.Text = 'This run has no "after" measurement yet: it is taken after the next restart.' }
    }

    [void]$window.ShowDialog()
    if ($script:UdpReport.Timer) { $script:UdpReport.Timer.Stop() }
}

# UDP.ps1 -Report: started once by the scheduled task after the restart.
function Show-UdpReportMode {
    param([Parameter(Mandatory)][hashtable]$Context)

    Unregister-UdpReportTask
    $lastRun = (Get-UdpState).LastRun
    if (-not $lastRun -or -not $lastRun.before) {
        Write-UdpLog 'No "before" measurement was found; there is nothing to compare.' -Level Warning
        return
    }
    Initialize-UdpApplication -Root $Context.Root
    Show-UdpReportWindow -Context $Context -LastRun $lastRun -Measure:([bool]$lastRun.reportPending)

    # The copy of UDP kept for this report is no longer needed.
    $copy = Join-Path $env:ProgramData 'UDP\app'
    if ((Resolve-Path -LiteralPath $Context.Root).Path.TrimEnd('\') -eq $copy) {
        Remove-Item -LiteralPath $copy -Recurse -Force -ErrorAction SilentlyContinue
    }
}
