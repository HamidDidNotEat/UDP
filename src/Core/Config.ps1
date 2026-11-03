# Loads config/tools.json, the single file that lists every external source UDP uses.

function Import-UdpConfig {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path"
    }

    $json = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    try {
        $config = $json | ConvertFrom-Json
    }
    catch {
        throw "config/tools.json is not valid JSON: $($_.Exception.Message)"
    }

    if ($config.schemaVersion -ne 1) {
        throw "config/tools.json has schemaVersion '$($config.schemaVersion)', this version of UDP expects 1."
    }

    foreach ($id in 'win11debloat', 'shutup10', 'bcu', 'browser', 'edgeRemoval', 'nvcleanstall', 'autoruns') {
        if (-not $config.tools.$id) {
            throw "config/tools.json is missing the '$id' tool entry."
        }
    }

    return $config
}

function Get-UdpToolConfig {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Id
    )
    $tool = $Context.Config.tools.$Id
    if (-not $tool) { throw "Unknown tool id '$Id' in config/tools.json." }
    return $tool
}

# Expands %ProgramFiles%-style variables used in config paths.
function Expand-UdpPath {
    param([Parameter(Mandatory)][string]$Path)
    return [Environment]::ExpandEnvironmentVariables($Path)
}

# Creates (or empties) a folder for one step under %TEMP%\UDP\work.
function New-UdpWorkFolder {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$Name
    )
    $path = Join-Path $Context.WorkDir $Name
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}
