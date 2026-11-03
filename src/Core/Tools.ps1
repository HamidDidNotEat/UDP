# Getting a verified copy of a portable tool (ShutUp10++, Autoruns).
# Sources are tried in the order set by "preferredSource" in config/tools.json.
# A download or install failure moves on to the next source. A signature mismatch stops
# immediately: the step is skipped and the reason is logged.

function Get-UdpPortableTool {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ToolId,
        [Parameter(Mandatory)][string]$ExeName
    )

    $tool = Get-UdpToolConfig -Context $Context -Id $ToolId
    $order = @('direct', 'winget')
    if ($tool.preferredSource -eq 'winget') { $order = @('winget', 'direct') }

    foreach ($source in $order) {
        try {
            if ($source -eq 'direct' -and $tool.direct) {
                return Get-UdpPortableFromDirect -Context $Context -ToolId $ToolId -Tool $tool -ExeName $ExeName
            }
            if ($source -eq 'winget' -and $tool.winget) {
                if (-not (Get-UdpWingetPath)) {
                    Write-UdpLog "winget is not available, cannot use it for $($tool.name)." -Level Warning
                    continue
                }
                return Get-UdpPortableFromWinget -Context $Context -Tool $tool -ExeName $ExeName
            }
        }
        catch [System.Security.SecurityException] {
            throw
        }
        catch {
            Write-UdpLog "Getting $($tool.name) via $source failed: $($_.Exception.Message)" -Level Warning
        }
    }
    throw "Could not get a verified copy of $($tool.name) from any source."
}

function Assert-UdpSignature {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Tool
    )
    $check = Test-UdpSignature -Path $Path -ExpectedSigner $Tool.integrity.expectedSigner
    if (-not $check.Valid) {
        throw (New-Object System.Security.SecurityException("$($Tool.name) failed the signature check ($($check.Reason)). The step is skipped for safety."))
    }
}

function Get-UdpPortableFromDirect {
    param([hashtable]$Context, [string]$ToolId, $Tool, [string]$ExeName)

    $folder = New-UdpWorkFolder -Context $Context -Name $ToolId
    $file = Join-Path $folder $Tool.direct.fileName
    Invoke-UdpDownload -Uri $Tool.direct.url -OutFile $file | Out-Null

    $exe = $file
    if ($Tool.direct.archive -eq 'zip') {
        $extracted = Join-Path $folder 'extracted'
        Expand-Archive -LiteralPath $file -DestinationPath $extracted -Force
        $exe = Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter $ExeName | Select-Object -First 1 -ExpandProperty FullName
        if (-not $exe) { throw "$ExeName was not found in $($Tool.direct.fileName)." }
    }

    Assert-UdpSignature -Path $exe -Tool $Tool
    return $exe
}

function Get-UdpPortableFromWinget {
    param([hashtable]$Context, $Tool, [string]$ExeName)

    $wasInstalled = Test-UdpWingetPackageInstalled -Id $Tool.winget
    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would install $($Tool.winget) with winget and use it once" -Level DryRun
        return $null
    }

    $install = Install-UdpWingetPackage -Context $Context -Id $Tool.winget
    if (-not $install.Success) { throw "winget install failed (exit code $($install.ExitCode))." }

    $candidates = @(Find-UdpWingetPortableFile -Id $Tool.winget -Filter $ExeName)
    if ($candidates.Count -eq 0) { $candidates = @(Find-UdpWingetPortableFile -Id $Tool.winget -Filter '*.exe') }
    if ($candidates.Count -eq 0) { throw "winget installed $($Tool.winget) but the program file was not found." }

    $exe = $candidates[0].FullName
    Assert-UdpSignature -Path $exe -Tool $Tool

    if (-not $wasInstalled) {
        Register-UdpCleanup -Description "Uninstall $($Tool.name) (installed by winget for this run only)" -Data @{ Id = $Tool.winget } -Action {
            param($Context, $Data)
            Uninstall-UdpWingetPackage -Context $Context -Id $Data.Id | Out-Null
        }
    }
    return $exe
}
