# %ProgramData%\UDP\state.json remembers what UDP changed that it can undo later: browser extension
# policies and the Windows policies UDP sets (taskbar layout, default apps). Only entries listed
# here are ever removed by a revert.

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
    $system = @()
    if ($state -and $state.systemPolicies) {
        foreach ($entry in @($state.systemPolicies)) {
            $system += @{
                Name    = [string]$entry.name
                Key     = [string]$entry.key
                Values  = @($entry.values | ForEach-Object { [string]$_ })
                File    = [string]$entry.file
                Version = [int]$entry.version
                Browser = [string]$entry.browser
            }
        }
    }
    return @{ BrowserPolicies = $policies; SystemPolicies = $system }
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
    $system = @()
    foreach ($entry in @($State.SystemPolicies | Where-Object { $_ })) {
        $system += [ordered]@{
            name    = $entry.Name
            key     = $entry.Key
            values  = @($entry.Values)
            file    = $entry.File
            version = $entry.Version
            browser = $entry.Browser
        }
    }
    $document = [ordered]@{
        version         = 1
        updated         = (Get-Date).ToString('s')
        browserPolicies = @($policies)
        systemPolicies  = @($system)
    }
    $json = ConvertTo-Json -InputObject $document -Depth 6
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}
