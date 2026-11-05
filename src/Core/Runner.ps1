# Runs the selected steps one after another in a background runspace, so the window stays
# responsive. The runner and the window share one synchronized hashtable ($Context.Sync):
# - LogQueue / Progress / CurrentStep / StepStates: read by a DispatcherTimer in the window.
# - Request / Response / ResponseEvent: the runner asks a question and waits for the click.

function New-UdpStepResult {
    param(
        [Parameter(Mandatory)][ValidateSet('Success', 'Skipped', 'Failed')][string]$Status,
        [string]$Message = ''
    )
    $result = [pscustomobject]@{ Status = $Status; Message = $Message }
    $result.PSObject.TypeNames.Insert(0, 'UDP.StepResult')
    return $result
}

function New-UdpButton {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Id,
        [Parameter(Mandatory, Position = 1)][string]$Label,
        [switch]$Primary
    )
    return [pscustomobject]@{ Id = $Id; Label = $Label; Primary = [bool]$Primary }
}

function New-UdpSync {
    return [hashtable]::Synchronized(@{
            LogQueue      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
            LogLock       = New-Object object
            Progress      = 0
            CurrentStep   = ''
            StepStates    = [hashtable]::Synchronized(@{})
            Request       = $null
            Response      = $null
            ResponseEvent = New-Object System.Threading.AutoResetEvent($false)
            Aborted       = $false
            Finished      = $false
            Results       = $null
            FatalError    = $null
        })
}

# Shows a page in the window (briefing, failure question, confirmation, file picker) and blocks
# the runner until the user answers. Returns the Id of the clicked button (or a file path).
function Request-UdpDecision {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][ValidateSet('Briefing', 'Failure', 'Confirm', 'Info', 'PickFile')][string]$Kind,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [object[]]$Buttons,
        [string]$FileFilter
    )

    $sync = $Context.Sync
    if (-not $sync -or $sync.AutoAnswer) {
        # No window (tests/Test-UDP.ps1): take the primary answer.
        $primary = @($Buttons | Where-Object { $_.Primary }) | Select-Object -First 1
        if ($primary) { return $primary.Id }
        return ''
    }

    Write-UdpLog "Waiting for you: $Title" -Level Info
    $sync.Response = $null
    $sync.Request = [pscustomobject]@{
        Id         = [guid]::NewGuid().ToString()
        Kind       = $Kind
        Title      = $Title
        Body       = $Body
        Buttons    = @($Buttons)
        FileFilter = $FileFilter
    }
    [void]$sync.ResponseEvent.WaitOne()
    $answer = [string]$sync.Response
    $sync.Request = $null
    Write-UdpLog "Answer: $answer" -Level Detail
    return $answer
}

function Set-UdpStepState {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Status,
        [string]$Message = ''
    )
    if ($Context.Sync) {
        $Context.Sync.StepStates[$Id] = [pscustomobject]@{ Status = $Status; Message = $Message }
    }
}

# Actions to run once all steps are done (for example: uninstall a tool installed for this run only).
$script:UdpCleanupActions = New-Object System.Collections.ArrayList

function Register-UdpCleanup {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action,
        [hashtable]$Data = @{}
    )
    [void]$script:UdpCleanupActions.Add([pscustomobject]@{ Description = $Description; Action = $Action; Data = $Data })
}

function Invoke-UdpCleanup {
    param([Parameter(Mandatory)][hashtable]$Context)

    for ($i = $script:UdpCleanupActions.Count - 1; $i -ge 0; $i--) {
        $item = $script:UdpCleanupActions[$i]
        Write-UdpLog "Cleanup: $($item.Description)" -Level Info
        try { & $item.Action $Context $item.Data }
        catch { Write-UdpLog "Cleanup failed: $($_.Exception.Message)" -Level Warning }
    }
    $script:UdpCleanupActions.Clear()

    if (Test-Path -LiteralPath $Context.WorkDir) {
        Write-UdpLog "Removing the temporary folder $($Context.WorkDir)" -Level Info
        Remove-Item -LiteralPath $Context.WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The ordered list of steps that will run for this selection (enabled and available on this PC).
function Get-UdpRunPlan {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$Selection
    )
    $plan = @()
    foreach ($step in (Get-UdpStepCatalog | Sort-Object Order)) {
        $options = $Selection[$step.Id]
        if (-not $options -or -not $options.Enabled) { continue }
        $availability = & $step.Available -Context $Context
        if (-not $availability.Available) { continue }
        $plan += $step
    }
    return $plan
}

# Runs a step function and keeps only its result object, so stray pipeline output from a
# command inside the step cannot be mistaken for the result.
function Invoke-UdpStepFunction {
    param([string]$FunctionName, [hashtable]$Context, [hashtable]$Options)
    $output = @(& $FunctionName -Context $Context -Options $Options)
    $result = $output | Where-Object { $_ -and $_.PSObject.TypeNames -contains 'UDP.StepResult' } | Select-Object -Last 1
    if (-not $result) { $result = New-UdpStepResult -Status Failed -Message 'The step returned no result.' }
    return $result
}

function Invoke-UdpRun {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$Selection
    )

    $sync = $Context.Sync
    $plan = @(Get-UdpRunPlan -Context $Context -Selection $Selection)
    $total = $plan.Count + 1
    $done = 0
    $results = New-Object System.Collections.ArrayList

    $mode = ''
    if ($Context.DryRun) { $mode = ' (DRY RUN: nothing will be changed)' }
    Write-UdpLog "UDP run started$mode" -Level Step
    Write-UdpLog ('Order: Restore point -> {0}' -f (($plan | ForEach-Object { $_.Name }) -join ' -> ')) -Level Info

    # 0. Measure the PC before any change, for the before/after report.
    $before = $null
    if (-not $Context.DryRun) {
        $sync.CurrentStep = 'Measuring this PC before any change'
        Write-UdpLog 'Measuring this PC before any change (for the before/after report)' -Level Info
        try { $before = Get-UdpSnapshot }
        catch { Write-UdpLog "Could not measure this PC: $($_.Exception.Message)" -Level Warning }
    }

    # 1. Restore point
    Set-UdpStepState -Context $Context -Id 'restorepoint' -Status 'Running'
    $sync.CurrentStep = 'System Restore point'
    Write-UdpLog '=== System Restore point ===' -Level Step
    $restore = New-UdpRestorePoint -Context $Context
    [void]$results.Add([pscustomobject]@{ Id = 'restorepoint'; Name = 'System Restore point'; Status = $restore.Status; Message = $restore.Message })
    Set-UdpStepState -Context $Context -Id 'restorepoint' -Status $restore.Status -Message $restore.Message
    Write-UdpLog $restore.Message -Level $(if ($restore.Status -eq 'Failed') { 'Error' } else { 'Success' })

    if ($restore.Status -eq 'Failed') {
        $answer = Request-UdpDecision -Context $Context -Kind 'Failure' -Title 'The restore point could not be created' -Body (
            "$($restore.Message)`r`n`r`n" +
            "The restore point is the safety net that lets you undo UDP's changes. " +
            "Without it, some changes (removed apps, uninstalled programs) are harder to undo.`r`n`r`n" +
            'Do you want to continue without a restore point?') -Buttons @(
            (New-UdpButton 'abort' 'Stop here' -Primary),
            (New-UdpButton 'continue' 'Continue without a restore point'))
        if ($answer -ne 'continue') { $sync.Aborted = $true }
    }
    $done++
    $sync.Progress = [int](100 * $done / $total)

    # 2. Steps, strictly in order
    for ($index = 0; $index -lt $plan.Count; $index++) {
        $step = $plan[$index]

        if ($sync.Aborted) {
            $result = New-UdpStepResult -Status Skipped -Message 'Not run: the run was stopped.'
        }
        else {
            Set-UdpStepState -Context $Context -Id $step.Id -Status 'Running'
            $sync.CurrentStep = $step.Name
            Write-UdpLog "=== $($step.Name) ===" -Level Step
            try {
                $result = Invoke-UdpStepFunction -FunctionName $step.Invoke -Context $Context -Options $Selection[$step.Id]
            }
            catch {
                $result = New-UdpStepResult -Status Failed -Message $_.Exception.Message
                Write-UdpLog ($_ | Out-String).Trim() -Level Error
            }
            $level = @{ Success = 'Success'; Skipped = 'Warning'; Failed = 'Error' }[$result.Status]
            Write-UdpLog "$($step.Name): $($result.Status). $($result.Message)" -Level $level
        }

        [void]$results.Add([pscustomobject]@{ Id = $step.Id; Name = $step.Name; Status = $result.Status; Message = $result.Message })
        Set-UdpStepState -Context $Context -Id $step.Id -Status $result.Status -Message $result.Message
        $done++
        $sync.Progress = [int](100 * $done / $total)

        $remaining = $plan.Count - $index - 1
        if ($result.Status -eq 'Failed' -and $remaining -gt 0 -and -not $sync.Aborted) {
            $next = $plan[$index + 1].Name
            $answer = Request-UdpDecision -Context $Context -Kind 'Failure' -Title "$($step.Name) failed" -Body (
                "$($result.Message)`r`n`r`nThe details are in the log below and in $($Context.LogFile).`r`n`r`n" +
                "Continue with the next step ($next), or stop here?") -Buttons @(
                (New-UdpButton 'continue' 'Continue' -Primary),
                (New-UdpButton 'abort' 'Stop here'))
            if ($answer -ne 'continue') { $sync.Aborted = $true }
        }
    }

    # 3. Remember this run; schedule the before/after report for the next sign-in.
    if ($Context.DryRun) {
        if ($Selection.Report) { Write-UdpLog '[dry run] would schedule the before/after report for the next sign-in' -Level DryRun }
    }
    else {
        $reportPending = [bool]($Selection.Report -and $before)
        if ($reportPending) {
            try { Register-UdpReportTask -Context $Context }
            catch {
                $reportPending = $false
                Write-UdpLog "Could not schedule the before/after report: $($_.Exception.Message)" -Level Warning
            }
        }
        else {
            # No report this time: remove a task left from an earlier run that never showed its report.
            Unregister-UdpReportTask
        }
        $sync.ReportScheduled = $reportPending
        Save-UdpLastRun -Context $Context -Before $before -Results $results.ToArray() -ReportPending $reportPending
    }

    # 4. Cleanup
    $sync.CurrentStep = 'Cleaning up'
    Invoke-UdpCleanup -Context $Context
    $sync.CurrentStep = 'Done'
    $sync.Progress = 100
    Write-UdpLog "UDP run finished. Log file: $($Context.LogFile)" -Level Step
    $sync.Results = $results.ToArray()
}

# Starts Invoke-UdpRun in a background runspace. The runspace loads the same source files.
function Start-UdpRunner {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$Selection
    )

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    try { $sessionState.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { }

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($sessionState)
    $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $runspace.Open()

    $script = {
        param($Context, $Selection)
        $ProgressPreference = 'SilentlyContinue'
        foreach ($folder in 'src\Core', 'src\Steps') {
            foreach ($file in (Get-ChildItem -Path (Join-Path $Context.Root $folder) -Filter '*.ps1' | Sort-Object Name)) {
                . $file.FullName
            }
        }
        Set-UdpLogContext -Context $Context
        try {
            Invoke-UdpRun -Context $Context -Selection $Selection
        }
        catch {
            $Context.Sync.FatalError = ($_ | Out-String).Trim()
            Write-UdpLog "Unexpected error, the run stopped: $($Context.Sync.FatalError)" -Level Error
        }
        finally {
            $Context.Sync.Finished = $true
        }
    }

    $powershell = [System.Management.Automation.PowerShell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript($script.ToString()).AddArgument($Context).AddArgument($Selection)
    $handle = $powershell.BeginInvoke()

    return [pscustomobject]@{ PowerShell = $powershell; Runspace = $runspace; Handle = $handle }
}
