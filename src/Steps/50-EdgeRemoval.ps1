# Step 5: Edge removal with AveYo's Edge_Removal.bat (https://github.com/AveYo/fox).
#
# Why UDP does not simply run the .bat file:
#   - Its options are variables at the top of the script and default to also removing WebView2,
#     Widgets and Gaming Services. UDP must always keep WebView2.
#   - Its launcher re-opens itself in a new PowerShell window that stays open (-NoExit), so UDP
#     could not tell when it has finished.
# So UDP downloads the file pinned in config/tools.json, checks its SHA256, takes the PowerShell
# part that the .bat embeds, sets the three option lines and runs that part directly with no
# window, waiting for it to finish. The exact option lines used are written to the log.

function Test-UdpEdgeRemovalAvailable {
    param([hashtable]$Context)
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    if (-not $Context.System.EdgeInstalled) { return New-UdpAvailability $false 'Microsoft Edge is not installed.' }
    return New-UdpAvailability $true
}

function Get-UdpEdgeRemovalPlan {
    param([hashtable]$Context, [hashtable]$Options)
    $tool = Get-UdpToolConfig -Context $Context -Id 'edgeRemoval'
    $extra = @()
    if ($Options.RemoveWidgets) { $extra += 'Widgets' }
    if ($Options.RemoveXSocial) { $extra += 'Gaming Services' }
    $also = 'nothing else'
    if ($extra.Count -gt 0) { $also = $extra -join ' and ' }
    return @(
        "Download Edge_Removal.bat (AveYo/fox, commit $($tool.commit.Substring(0, 7))) and check its SHA256",
        "Remove Microsoft Edge and keep WebView2. Also remove: $also",
        'Run it with no window, wait for Edge''s own uninstaller to finish, then check that Edge is gone and WebView2 is still there'
    )
}

# Returns the PowerShell part of Edge_Removal.bat with the options set, or throws if the file
# layout is not the one UDP expects (in that case nothing is run).
function Get-UdpEdgeRemovalPayload {
    param([string]$ScriptText, $Tool, [hashtable]$Options)

    $lines = $ScriptText -split "`r?`n"
    $start = -1
    $end = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($start -lt 0 -and $lines[$i].TrimEnd() -ceq $Tool.payloadStartLine) { $start = $i; continue }
        if ($start -ge 0 -and $lines[$i].StartsWith($Tool.payloadEndPrefix)) { $end = $i; break }
    }
    if ($start -lt 0 -or $end -lt 0) { throw 'Edge_Removal.bat does not have the expected layout; nothing was run.' }

    $payload = ($lines[($start + 1)..($end - 1)] -join "`r`n")
    # The .bat stores its payload in a PowerShell here-string and uses $@ / @$ as stand-ins for
    # the nested here-string markers; it swaps them back before running. Do the same.
    $payload = $payload.Replace('$@', "'@").Replace('@$', "@'")

    $wanted = [ordered]@{
        webview = 0
        widgets = [int][bool]$Options.RemoveWidgets
        xsocial = [int][bool]$Options.RemoveXSocial
    }
    foreach ($name in $wanted.Keys) {
        $original = $Tool.optionLines.$name
        $count = ([regex]::Matches($payload, [regex]::Escape($original))).Count
        if ($count -ne 1) { throw "Option line '$original' found $count times in Edge_Removal.bat (expected once); nothing was run." }
        $replacement = $original -replace '= 1$', "= $($wanted[$name])"
        $payload = $payload.Replace($original, $replacement)
        Write-UdpLog "Edge_Removal option: $replacement" -Level Info
    }
    return $payload
}

function Invoke-UdpEdgeRemoval {
    param([hashtable]$Context, [hashtable]$Options)

    $tool = Get-UdpToolConfig -Context $Context -Id 'edgeRemoval'

    # Never leave the user without a browser.
    $browsers = @(Get-UdpInstalledBrowsers)
    if ($browsers.Count -eq 0 -and -not $Context.DryRun) {
        $answer = Request-UdpDecision -Context $Context -Kind 'Confirm' -Title 'No other browser is installed' -Body (
            "UDP found no browser other than Edge on this PC. If you remove Edge now, you will have no web browser.`r`n`r`n" +
            "You can still download one later from another device, but it is easier to install one first (go back and enable the 'Alternative browser' step).") -Buttons @(
            (New-UdpButton 'skip' 'Keep Edge' -Primary),
            (New-UdpButton 'remove' 'Remove Edge anyway'))
        if ($answer -ne 'remove') { return New-UdpStepResult -Status Skipped -Message 'Edge kept: no other browser is installed.' }
    }
    else {
        Write-UdpLog "Other browsers found: $($browsers -join ', ')" -Level Info
    }

    $folder = New-UdpWorkFolder -Context $Context -Name 'edge'
    $download = Join-Path $folder 'Edge_Removal.bat.txt'
    Invoke-UdpDownload -Uri $tool.url -OutFile $download | Out-Null
    if (-not (Test-UdpFileHash -Path $download -ExpectedSha256 $tool.sha256)) {
        return New-UdpStepResult -Status Skipped -Message 'Edge_Removal.bat does not match the SHA256 pinned in config/tools.json; skipped for safety.'
    }

    try {
        $payload = Get-UdpEdgeRemovalPayload -ScriptText ([System.IO.File]::ReadAllText($download)) -Tool $tool -Options $Options
    }
    catch {
        return New-UdpStepResult -Status Skipped -Message $_.Exception.Message
    }

    $payloadPath = Join-Path $folder 'Edge_Removal.ps1'
    [System.IO.File]::WriteAllText($payloadPath, $payload, (New-Object System.Text.UTF8Encoding($true)))
    Write-UdpLog "Prepared $payloadPath" -Level Detail

    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$payloadPath`"" -Level DryRun
        return New-UdpStepResult -Status Success -Message 'Dry run: Edge not removed.'
    }

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $exitCode = Invoke-UdpProcess -FilePath $powershell -Label 'Edge_Removal' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $payloadPath)

    # The script restarts Explorer; make sure it is running again.
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

    $edgeGone = Wait-UdpEdgeRemoved -TimeoutSeconds 300
    $webView = Test-UdpWebView2Installed
    Write-UdpLog "WebView2 Runtime after removal: $(if ($webView) { 'present' } else { 'NOT FOUND' })" -Level Info
    if ($edgeGone -and $webView) {
        return New-UdpStepResult -Status Success -Message 'Edge removed, WebView2 kept. Edge may come back after a major Windows update; run UDP again if it does.'
    }
    if ($edgeGone -and -not $Context.System.WebView2Installed) {
        return New-UdpStepResult -Status Success -Message 'Edge removed. WebView2 was not installed before UDP ran either; some apps may ask you to install it.'
    }
    if ($edgeGone) {
        return New-UdpStepResult -Status Failed -Message 'Edge was removed but WebView2 is missing afterwards. Reinstall it from https://developer.microsoft.com/microsoft-edge/webview2/'
    }
    return New-UdpStepResult -Status Failed -Message "Edge is still installed after waiting 5 minutes ($(Get-UdpEdgeLeftoverText)). Script exit code: $exitCode. See the log for details."
}

function Get-UdpEdgeLeftoverText {
    $left = @()
    if (Test-UdpEdgeUninstallEntry) { $left += 'its entry in Settings > Apps is still there' }
    foreach ($path in @(Get-UdpEdgeExePaths)) { $left += "$path still exists" }
    if ($left.Count -eq 0) { return 'nothing left' }
    return ($left -join '; ')
}

# Edge's uninstaller keeps running in the background after AveYo's script ends (it hands over to a
# copy of itself), so checking right away reports Edge as still installed. Wait until both its
# Settings > Apps entry and msedge.exe are gone, or until the timeout.
function Wait-UdpEdgeRemoved {
    param([int]$TimeoutSeconds = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $announced = $false
    while ($true) {
        if (-not (Test-UdpEdgeInstalled)) {
            Write-UdpLog 'Edge is gone: no entry in Settings > Apps and no msedge.exe.' -Level Info
            return $true
        }
        if ((Get-Date) -ge $deadline) {
            Write-UdpLog "Edge is still present after waiting: $(Get-UdpEdgeLeftoverText)" -Level Warning
            return $false
        }
        if (-not $announced) {
            Write-UdpLog "Waiting for Edge's own uninstaller to finish (up to $([int]($TimeoutSeconds / 60)) minutes): $(Get-UdpEdgeLeftoverText)" -Level Info
            $announced = $true
        }
        Start-Sleep -Seconds 3
    }
}
