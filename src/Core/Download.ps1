# Downloads from official sources over TLS 1.2, with retries, plus helpers for GitHub releases.

function Initialize-UdpNetwork {
    # Windows PowerShell 5.1 may default to older protocols; make sure TLS 1.2 is enabled.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Invoke-UdpDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [int]$Retries = 3
    )

    Initialize-UdpNetwork
    # The progress bar makes Invoke-WebRequest very slow in Windows PowerShell 5.1.
    $ProgressPreference = 'SilentlyContinue'

    $lastError = $null
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Write-UdpLog "Downloading $Uri" -Level Detail
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -UserAgent 'UDP' -ErrorAction Stop
            $file = Get-Item -LiteralPath $OutFile
            Write-UdpLog ('Downloaded {0} ({1:N1} MB)' -f $file.Name, ($file.Length / 1MB)) -Level Detail
            return $file
        }
        catch {
            $lastError = $_
            Write-UdpLog "Download attempt $attempt of $Retries failed: $($_.Exception.Message)" -Level Warning
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
    throw "Download failed: $Uri ($($lastError.Exception.Message))"
}

function Get-UdpGitHubLatestRelease {
    param([Parameter(Mandatory)][string]$Repo)

    Initialize-UdpNetwork
    $uri = "https://api.github.com/repos/$Repo/releases/latest"
    Write-UdpLog "Looking up the latest release of $Repo" -Level Detail
    $headers = @{ 'User-Agent' = 'UDP'; 'Accept' = 'application/vnd.github+json' }
    return Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing -ErrorAction Stop
}

# Finds one asset of a release, by exact name or by wildcard pattern.
function Get-UdpGitHubAsset {
    param(
        [Parameter(Mandatory)]$Release,
        [string]$Name,
        [string]$Pattern
    )
    $assets = @($Release.assets)
    if ($Name) { $match = @($assets | Where-Object { $_.name -ceq $Name }) }
    else { $match = @($assets | Where-Object { $_.name -like $Pattern }) }

    if ($match.Count -eq 0) {
        throw "Release $($Release.tag_name) has no asset matching '$Name$Pattern'."
    }
    return $match[0]
}

# GitHub publishes a SHA256 digest for every release asset ("sha256:<hex>").
function Get-UdpGitHubAssetSha256 {
    param([Parameter(Mandatory)]$Asset)
    if ($Asset.digest -and $Asset.digest -match '^sha256:([0-9a-fA-F]{64})$') {
        return $Matches[1].ToLowerInvariant()
    }
    return $null
}

# Reads the expected hash of one file from a SHA256SUMS text ("<64 hex>  <file name>" per line).
function Get-UdpHashFromSums {
    param(
        [Parameter(Mandatory)][string]$SumsText,
        [Parameter(Mandatory)][string]$FileName
    )
    foreach ($line in ($SumsText -split "`r?`n")) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -ceq $FileName) {
            return $Matches[1].ToLowerInvariant()
        }
    }
    return $null
}
