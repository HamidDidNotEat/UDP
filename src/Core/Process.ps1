# Starting external programs. UDP runs them strictly one at a time:
# - Invoke-UdpProcess: non-interactive tools, no visible window, output copied into the UDP log.
# - Invoke-UdpInteractiveProcess: tools the user works with; UDP waits until they are closed.

# Quotes one command-line argument so the target program receives it unchanged.
function Format-UdpArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Join-UdpArguments {
    param([string[]]$ArgumentList)
    if (-not $ArgumentList) { return '' }
    return (($ArgumentList | ForEach-Object { Format-UdpArgument $_ }) -join ' ')
}

# Block characters U+2580..U+259F, which winget uses to draw progress bars.
$script:UdpBlockCharPattern = '[' + [char]0x2580 + '-' + [char]0x259F + ']'

# Removes terminal colour and cursor codes (ESC [ ...) that some scripts print, so the log stays readable.
function ConvertTo-UdpPlainText {
    param([AllowEmptyString()][string]$Text)
    return ($Text -replace '\x1b\[[0-9;?]*[ -/]*[@-~]', '')
}

# Reads what was appended to a redirected output file since the last call and logs complete lines.
function Read-UdpProcessOutput {
    param(
        [Parameter(Mandatory)][hashtable]$Reader,
        [switch]$Final
    )

    if (-not (Test-Path -LiteralPath $Reader.Path)) { return }

    $stream = $null
    try {
        $stream = New-Object System.IO.FileStream($Reader.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        if ($stream.Length -le $Reader.Position) { return }
        [void]$stream.Seek($Reader.Position, [System.IO.SeekOrigin]::Begin)
        $buffer = New-Object byte[] ($stream.Length - $Reader.Position)
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $Reader.Position += $read
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }

    # Tools write either UTF-8 or the console code page; try UTF-8 first.
    $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
    if ($text.IndexOf([char]0xFFFD) -ge 0) {
        $text = [Console]::OutputEncoding.GetString($buffer, 0, $read)
    }

    $text = $Reader.Pending + $text
    $parts = @($text -split "`r`n|`n|`r")
    if ($Final) { $Reader.Pending = '' }
    else {
        # The last part may be an unfinished line; keep it for the next read.
        $Reader.Pending = $parts[-1]
        if ($parts.Count -gt 1) { $parts = $parts[0..($parts.Count - 2)] }
        else { $parts = @() }
    }

    foreach ($part in $parts) {
        $clean = (ConvertTo-UdpPlainText $part).Trim()
        if ($clean -eq '') { continue }
        # Skip spinner and progress-bar lines (winget draws them with block characters).
        if ($clean -match '^[\-\\|/\s]+$') { continue }
        if ($clean -match $script:UdpBlockCharPattern) { continue }
        Write-UdpLog "  $clean" -Level Detail
    }
}

function Invoke-UdpProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$Label
    )

    if (-not $Label) { $Label = Split-Path -Leaf $FilePath }
    $arguments = Join-UdpArguments -ArgumentList $ArgumentList
    Write-UdpLog "Running: $FilePath $arguments" -Level Detail

    $workDir = $script:UdpLogContext.WorkDir
    if (-not (Test-Path -LiteralPath $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outFile = Join-Path $workDir "process_$id.out.txt"
    $errFile = Join-Path $workDir "process_$id.err.txt"
    # Input comes from an empty file: a tool that unexpectedly waits for a key press then fails
    # (and shows up in the log) instead of waiting forever in a window nobody can see.
    $inFile = Join-Path $workDir "process_$id.in.txt"
    [System.IO.File]::WriteAllText($inFile, '')

    $startParams = @{
        FilePath               = $FilePath
        WindowStyle            = 'Hidden'
        PassThru               = $true
        RedirectStandardInput  = $inFile
        RedirectStandardOutput = $outFile
        RedirectStandardError  = $errFile
        ErrorAction            = 'Stop'
    }
    if ($arguments) { $startParams.ArgumentList = $arguments }
    if ($WorkingDirectory) { $startParams.WorkingDirectory = $WorkingDirectory }

    $process = Start-Process @startParams
    # Reading Handle once makes ExitCode available after the process ends (known PowerShell quirk).
    $null = $process.Handle

    $readers = @(
        @{ Path = $outFile; Position = 0; Pending = '' },
        @{ Path = $errFile; Position = 0; Pending = '' }
    )
    while (-not $process.HasExited) {
        foreach ($reader in $readers) { Read-UdpProcessOutput -Reader $reader }
        Start-Sleep -Milliseconds 300
    }
    $process.WaitForExit()
    foreach ($reader in $readers) { Read-UdpProcessOutput -Reader $reader -Final }

    Remove-Item -LiteralPath $outFile, $errFile, $inFile -Force -ErrorAction SilentlyContinue

    $exitCode = $process.ExitCode
    Write-UdpLog "$Label finished with exit code $exitCode" -Level Detail
    return $exitCode
}

function Invoke-UdpInteractiveProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        # Some programs hand over to a second copy of themselves and exit; keep waiting while any
        # process with this name is still running.
        [string]$WaitForProcessName
    )

    $arguments = Join-UdpArguments -ArgumentList $ArgumentList
    Write-UdpLog "Starting: $FilePath $arguments" -Level Detail

    $startParams = @{ FilePath = $FilePath; PassThru = $true; ErrorAction = 'Stop' }
    if ($arguments) { $startParams.ArgumentList = $arguments }
    if ($WorkingDirectory) { $startParams.WorkingDirectory = $WorkingDirectory }

    $process = Start-Process @startParams
    $null = $process.Handle
    $process.WaitForExit()

    if ($WaitForProcessName) {
        while (Get-Process -Name $WaitForProcessName -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 1
        }
    }

    Write-UdpLog "$(Split-Path -Leaf $FilePath) was closed" -Level Detail
    return $process.ExitCode
}
