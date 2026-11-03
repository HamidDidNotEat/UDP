# System Restore point created before any change. This is the main safety net of a UDP run.

$script:RestorePointKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$script:RestorePointFrequencyValue = 'SystemRestorePointCreationFrequency'

function New-UdpRestorePoint {
    param([Parameter(Mandatory)][hashtable]$Context)

    $drive = "$env:SystemDrive\"
    $description = 'UDP (Ultimate Debloat Pack) {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')

    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would enable System Protection on $drive and create the restore point '$description'" -Level DryRun
        return New-UdpStepResult -Status Success -Message 'Dry run: no restore point created.'
    }

    Write-UdpLog "Enabling System Protection on $drive (no change if it is already on)" -Level Info
    try {
        Enable-ComputerRestore -Drive $drive -ErrorAction Stop
    }
    catch {
        return New-UdpStepResult -Status Failed -Message "Could not enable System Protection on ${drive}: $($_.Exception.Message). It may be disabled by a group policy."
    }

    # Windows allows one restore point every 24 hours by default (value in minutes, 1440).
    # Set it to 0 for this one call and put the previous value back afterwards.
    $previous = $null
    $hadValue = $false
    $item = Get-ItemProperty -Path $script:RestorePointKey -Name $script:RestorePointFrequencyValue -ErrorAction SilentlyContinue
    if ($item) {
        $hadValue = $true
        $previous = $item.($script:RestorePointFrequencyValue)
    }

    try {
        Set-ItemProperty -Path $script:RestorePointKey -Name $script:RestorePointFrequencyValue -Value 0 -Type DWord -ErrorAction Stop
        Write-UdpLog "Creating restore point '$description' (this can take a minute)" -Level Info
        Checkpoint-Computer -Description $description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
    }
    catch {
        return New-UdpStepResult -Status Failed -Message "Restore point creation failed: $($_.Exception.Message)"
    }
    finally {
        if ($hadValue) {
            Set-ItemProperty -Path $script:RestorePointKey -Name $script:RestorePointFrequencyValue -Value $previous -Type DWord -ErrorAction SilentlyContinue
        }
        else {
            Remove-ItemProperty -Path $script:RestorePointKey -Name $script:RestorePointFrequencyValue -ErrorAction SilentlyContinue
        }
    }

    $latest = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1
    if ($latest -and $latest.Description -eq $description) {
        return New-UdpStepResult -Status Success -Message "Restore point created: '$description'."
    }
    return New-UdpStepResult -Status Failed -Message 'Windows did not report the new restore point.'
}
