# UDP (Ultimate Debloat Pack) bootstrap for the one-line start:
#
#   irm https://raw.githubusercontent.com/HamidDidNotEat/UDP/main/Get.ps1 | iex
#
# It downloads the latest UDP release (UDP.zip), checks it against the SHA256SUMS file published
# with the release, extracts it to %TEMP%\UDP\app and starts UDP.ps1 as administrator.
# The extracted files are deleted when UDP closes. Nothing else is downloaded by this script.

& {
    $repository = 'HamidDidNotEat/UDP'   # keep in sync with "project.repository" in config/tools.json
    $branch = 'main'

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $tempRoot = Join-Path $env:TEMP 'UDP'
    $appFolder = Join-Path $tempRoot 'app'
    $archive = Join-Path $tempRoot 'UDP.zip'
    $headers = @{ 'User-Agent' = 'UDP'; 'Accept' = 'application/vnd.github+json' }

    Write-Host 'UDP (Ultimate Debloat Pack)' -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $release = $null
        try {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/latest" -Headers $headers -UseBasicParsing
        }
        catch {
            Write-Host 'No published release found.' -ForegroundColor Yellow
        }

        $zipAsset = $null
        $sumsAsset = $null
        if ($release) {
            $zipAsset = @($release.assets | Where-Object { $_.name -ceq 'UDP.zip' }) | Select-Object -First 1
            $sumsAsset = @($release.assets | Where-Object { $_.name -ceq 'SHA256SUMS' }) | Select-Object -First 1
        }

        if ($zipAsset -and $sumsAsset) {
            Write-Host "> Downloading UDP $($release.tag_name)..."
            $sums = (Invoke-WebRequest -Uri $sumsAsset.browser_download_url -UseBasicParsing -UserAgent 'UDP').Content
            if ($sums -is [byte[]]) { $sums = [System.Text.Encoding]::UTF8.GetString($sums) }
            $expected = $null
            foreach ($line in ($sums -split "`r?`n")) {
                if ($line -match '^([0-9a-fA-F]{64})\s+\*?UDP\.zip\s*$') { $expected = $Matches[1].ToLowerInvariant() }
            }
            if (-not $expected) { throw 'SHA256SUMS does not list UDP.zip.' }

            Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $archive -UseBasicParsing -UserAgent 'UDP'
            $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $expected) {
                Remove-Item -LiteralPath $archive -Force
                throw "The downloaded UDP.zip does not match the published SHA256 (expected $expected, got $actual)."
            }
            Write-Host '> SHA256 verified.'
        }
        else {
            # Before the first release: use the current branch. It comes from the same repository as
            # this script, over HTTPS, but there is no published checksum to compare it with.
            Write-Host "> Downloading the '$branch' branch (no release checksum available)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri "https://github.com/$repository/archive/refs/heads/$branch.zip" -OutFile $archive -UseBasicParsing -UserAgent 'UDP'
        }

        if (Test-Path -LiteralPath $appFolder) { Remove-Item -LiteralPath $appFolder -Recurse -Force }
        Expand-Archive -LiteralPath $archive -DestinationPath $appFolder -Force
        Remove-Item -LiteralPath $archive -Force

        $script = Get-ChildItem -LiteralPath $appFolder -Filter 'UDP.ps1' -Recurse | Select-Object -First 1
        if (-not $script) { throw 'UDP.ps1 was not found in the downloaded archive.' }

        Write-Host '> Starting UDP (accept the administrator prompt)...'
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$($script.FullName)`""
        Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -Wait
    }
    catch {
        Write-Host "UDP could not start: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if (Test-Path -LiteralPath $appFolder) { Remove-Item -LiteralPath $appFolder -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
    }
}
