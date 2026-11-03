# %ProgramData%\UDP\state.json remembers what UDP changed that it can undo later
# (currently: browser extension policies). Only entries listed here are ever removed by a revert.

function Get-UdpStatePath {
    return (Join-Path $env:ProgramData 'UDP\state.json')
}

function Get-UdpState {
    $path = Get-UdpStatePath
    $state = $null
    if (Test-Path -LiteralPath $path) {
        try {
            $state = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        }
        catch {
            Write-UdpLog "state.json could not be read and will be recreated: $($_.Exception.Message)" -Level Warning
        }
    }

    $policies = @()
    if ($state -and $state.browserPolicies) {
        foreach ($entry in @($state.browserPolicies)) {
            $policies += @{
                Browser      = [string]$entry.browser
                Key          = [string]$entry.key
                ValueName    = [string]$entry.valueName
                ValueType    = [string]$entry.valueType
                ExtensionIds = @($entry.extensionIds | ForEach-Object { [string]$_ })
                CreatedValue = [bool]$entry.createdValue
                CreatedKey   = [bool]$entry.createdKey
            }
        }
    }
    return @{ BrowserPolicies = $policies }
}

function Save-UdpState {
    param([Parameter(Mandatory)][hashtable]$State)

    $path = Get-UdpStatePath
    $folder = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

    $policies = @()
    foreach ($entry in $State.BrowserPolicies) {
        $policies += [ordered]@{
            browser      = $entry.Browser
            key          = $entry.Key
            valueName    = $entry.ValueName
            valueType    = $entry.ValueType
            extensionIds = @($entry.ExtensionIds)
            createdValue = $entry.CreatedValue
            createdKey   = $entry.CreatedKey
        }
    }
    $document = [ordered]@{
        version         = 1
        updated         = (Get-Date).ToString('s')
        browserPolicies = @($policies)
    }
    $json = ConvertTo-Json -InputObject $document -Depth 6
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}
