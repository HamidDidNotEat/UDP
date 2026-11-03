# Step 7: Autoruns (Microsoft Sysinternals). Runs last, so it shows the startup entries that are
# left after all uninstalls. Manual review: UDP opens it and waits until it is closed.

function Test-UdpAutorunsAvailable {
    param([hashtable]$Context)
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    return New-UdpAvailability $true
}

function Get-UdpAutorunsExeName {
    param([hashtable]$Context)
    $tool = Get-UdpToolConfig -Context $Context -Id 'autoruns'
    switch ($Context.System.Architecture) {
        'arm64' { return $tool.exeNameArm64 }
        'x86' { return $tool.exeName32 }
        default { return $tool.exeName }
    }
}

function Get-UdpAutorunsPlan {
    param([hashtable]$Context, [hashtable]$Options)
    return @(
        'Download Autoruns from download.sysinternals.com and check that it is signed by Microsoft Corporation',
        'Show a short guide, then open Autoruns and wait until you close it'
    )
}

function Get-UdpAutorunsBriefing {
    return @'
Autoruns lists everything that starts with Windows: programs, services, drivers, scheduled tasks and more. It is a review tool: you decide what to switch off.

How to use it:
  1. Open the "Options" menu and tick "Hide Microsoft Entries" and "Hide Windows Entries", then press F5 to refresh. What is left is third-party software.
  2. Look at the "Logon", "Scheduled Tasks" and "Services" tabs first.
  3. To stop something from starting, UNTICK its checkbox. Do not delete entries: an unticked entry can be ticked again later, a deleted one cannot.
  4. Rows in yellow point to files that no longer exist, usually leftovers. Rows in pink have no verified publisher: look them up before changing them.
  5. Leave drivers, security software and anything you do not recognise alone.
  6. Close Autoruns when you are done. Changes take effect after the restart at the end.

The first time, Autoruns shows Microsoft's license terms: read them and accept to continue.
'@
}

function Invoke-UdpAutoruns {
    param([hashtable]$Context, [hashtable]$Options)

    try {
        $exe = Get-UdpPortableTool -Context $Context -ToolId 'autoruns' -ExeName (Get-UdpAutorunsExeName -Context $Context)
    }
    catch [System.Security.SecurityException] {
        return New-UdpStepResult -Status Skipped -Message $_.Exception.Message
    }

    if ($Context.DryRun) {
        Write-UdpLog '[dry run] would show the Autoruns guide, open Autoruns and wait until it is closed' -Level DryRun
        return New-UdpStepResult -Status Success -Message 'Dry run: Autoruns not opened.'
    }

    $answer = Request-UdpDecision -Context $Context -Kind 'Briefing' -Title 'Autoruns' -Body (Get-UdpAutorunsBriefing) -Buttons @(
        (New-UdpButton 'launch' 'Open Autoruns' -Primary),
        (New-UdpButton 'skip' 'Skip this step'))
    if ($answer -ne 'launch') { return New-UdpStepResult -Status Skipped -Message 'Skipped by you.' }

    Invoke-UdpInteractiveProcess -FilePath $exe -WaitForProcessName ([System.IO.Path]::GetFileNameWithoutExtension($exe)) | Out-Null
    return New-UdpStepResult -Status Success -Message 'Autoruns was opened and closed.'
}
