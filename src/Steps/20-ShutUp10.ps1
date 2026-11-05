# Step 2: O&O ShutUp10++ (https://www.oo-software.com/en/shutup10).
# GUI mode: UDP opens ShutUp10++ and waits until it is closed.
# Silent mode: imports the user's own exported config (config/ooshutup10.cfg) with
# "OOSU10.exe <file>.cfg /quiet", the syntax written by ShutUp10++ in the header of its exported files.
# UDP ships no .cfg, so no setting IDs are invented here.

function Get-UdpShutUp10ConfigPath {
    param([hashtable]$Context)
    $tool = Get-UdpToolConfig -Context $Context -Id 'shutup10'
    return (Join-Path $Context.Root (Join-Path 'config' $tool.userConfigFile))
}

function Test-UdpShutUp10Available {
    param([hashtable]$Context)
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    return New-UdpAvailability $true
}

function Get-UdpShutUp10Plan {
    param([hashtable]$Context, [hashtable]$Options)
    $lines = @('Download OOSU10.exe from oo-software.com and check that it is signed by O&O Software GmbH')
    if ($Options.Mode -eq 'Silent') {
        $lines += "Apply your exported settings silently: OOSU10.exe `"$(Get-UdpShutUp10ConfigPath -Context $Context)`" /quiet"
    }
    else {
        $lines += 'Show a short guide, then open ShutUp10++ and wait until you close it'
    }
    return $lines
}

function Get-UdpShutUp10Briefing {
    return @'
## What you will see
A list of Windows privacy settings. Each row has a switch: green means the protection is on. The icon next to it shows how safe it is: a green tick is recommended, a yellow sign is a limited recommendation, a red sign is not recommended.

## Step by step
1. Click the "Actions" menu at the top, then "Apply only recommended settings".
2. If ShutUp10++ asks to create a system restore point, click No: UDP already created one.
3. Optional: read the yellow items one by one and switch on the ones you understand. Leave the red ones alone.
4. Close ShutUp10++ with the X in the top-right corner.

## Do I need to save?
No. Each switch is applied as soon as you click it. There is no Save button.

> UDP continues automatically when you close ShutUp10++. To undo later: open it again and use "Actions > Undo all changes".
'@
}

function Invoke-UdpShutUp10 {
    param([hashtable]$Context, [hashtable]$Options)

    $tool = Get-UdpToolConfig -Context $Context -Id 'shutup10'

    if ($Options.Mode -eq 'Silent') {
        $configPath = Get-UdpShutUp10ConfigPath -Context $Context
        if (-not (Test-Path -LiteralPath $configPath)) {
            return New-UdpStepResult -Status Skipped -Message "Silent mode needs your exported settings at $configPath; the file was not found."
        }
    }

    try {
        $exe = Get-UdpPortableTool -Context $Context -ToolId 'shutup10' -ExeName $tool.exeName
    }
    catch [System.Security.SecurityException] {
        return New-UdpStepResult -Status Skipped -Message $_.Exception.Message
    }

    if ($Options.Mode -eq 'Silent') {
        if ($Context.DryRun) {
            Write-UdpLog "[dry run] would run: $exe `"$configPath`" /quiet" -Level DryRun
            return New-UdpStepResult -Status Success -Message 'Dry run: settings not applied.'
        }
        $exitCode = Invoke-UdpProcess -FilePath $exe -ArgumentList @($configPath, '/quiet') -Label 'ShutUp10++'
        if ($exitCode -ne 0) { return New-UdpStepResult -Status Failed -Message "ShutUp10++ exited with code $exitCode." }
        return New-UdpStepResult -Status Success -Message "Settings from $(Split-Path -Leaf $configPath) applied."
    }

    if ($Context.DryRun) {
        Write-UdpLog '[dry run] would show the ShutUp10++ guide, open ShutUp10++ and wait until it is closed' -Level DryRun
        return New-UdpStepResult -Status Success -Message 'Dry run: ShutUp10++ not opened.'
    }

    $answer = Request-UdpDecision -Context $Context -Kind 'Briefing' -Title 'O&O ShutUp10++' -Body (Get-UdpShutUp10Briefing) -Buttons @(
        (New-UdpButton 'launch' 'Open ShutUp10++' -Primary),
        (New-UdpButton 'skip' 'Skip this step'))
    if ($answer -ne 'launch') { return New-UdpStepResult -Status Skipped -Message 'Skipped by you.' }

    Invoke-UdpInteractiveProcess -FilePath $exe -WaitForProcessName ([System.IO.Path]::GetFileNameWithoutExtension($exe)) | Out-Null
    return New-UdpStepResult -Status Success -Message 'ShutUp10++ was opened and closed.'
}
