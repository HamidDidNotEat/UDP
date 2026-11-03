# Logging: one timestamped log file per run in %ProgramData%\UDP\logs.
# While a run is in progress, every line is also queued for the log panel in the window.

function Initialize-UdpLog {
    param([Parameter(Mandatory)][hashtable]$Context)

    $logDir = Join-Path $env:ProgramData 'UDP\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $Context.LogDir = $logDir
    $Context.LogFile = Join-Path $logDir ('UDP_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Set-UdpLogContext -Context $Context
}

# The log functions need the context (log file path and UI queue). The background runspace loads
# these files again, so it calls this to point the functions at the same context.
function Set-UdpLogContext {
    param([Parameter(Mandatory)][hashtable]$Context)
    $script:UdpLogContext = $Context
}

function Write-UdpLog {
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info', 'Step', 'Success', 'Warning', 'Error', 'Detail', 'DryRun')]
        [string]$Level = 'Info'
    )

    $ctx = $script:UdpLogContext
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $Message

    if ($ctx -and $ctx.LogFile) {
        $lock = $null
        if ($ctx.Sync) { $lock = $ctx.Sync.LogLock }
        if ($lock) { [System.Threading.Monitor]::Enter($lock) }
        try {
            # A second writer (for example an antivirus scan) can hold the file briefly, so retry a few times.
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    [System.IO.File]::AppendAllText($ctx.LogFile, $line + "`r`n", [System.Text.Encoding]::UTF8)
                    break
                }
                catch {
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        finally {
            if ($lock) { [System.Threading.Monitor]::Exit($lock) }
        }
    }

    if ($ctx -and $ctx.Sync) {
        $ctx.Sync.LogQueue.Enqueue([pscustomobject]@{ Level = $Level; Text = $line })
    }
    elseif (-not $ctx -or -not $ctx.Quiet) {
        # No window yet (or a console-only action such as -RevertBrowserPolicies): print to the console.
        Write-Host $line
    }
}
