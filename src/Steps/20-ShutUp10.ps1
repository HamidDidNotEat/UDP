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
ShutUp10++ shows Windows privacy settings as a list of switches. Green means the protection is on.

Suggested way to use it:
  1. Open the "Actions" menu and choose "Apply only recommended settings".
     Recommended settings are safe for almost everyone.
  2. Optionally go through the yellow "limited recommendation" items one by one.
     Leave the red "not recommended" ones alone unless you know what they do.
  3. If ShutUp10++ asks to create a restore point, you can say No: UDP already created one.
  4. Close ShutUp10++. UDP continues automatically.

To undo later: open ShutUp10++ again and use "Actions > Undo all changes".
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
