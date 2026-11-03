# The steps UDP can run, in execution order. Each step file provides three functions:
#   Available: Test-...    -> @{ Available = $true/$false; Reason = '...' }
#   Plan:      Get-...Plan -> lines describing what will happen (summary page and dry run)
#   Invoke:    Invoke-...  -> a UDP.StepResult (Success / Skipped / Failed)

function Get-UdpStepCatalog {
    return @(
        [pscustomobject]@{ Id = 'win11debloat'; Order = 10; Name = 'Win11Debloat'; Interactive = $false
            Available = 'Test-UdpWin11DebloatAvailable'; Plan = 'Get-UdpWin11DebloatPlan'; Invoke = 'Invoke-UdpWin11Debloat' }
        [pscustomobject]@{ Id = 'shutup10'; Order = 20; Name = 'O&O ShutUp10++'; Interactive = $true
            Available = 'Test-UdpShutUp10Available'; Plan = 'Get-UdpShutUp10Plan'; Invoke = 'Invoke-UdpShutUp10' }
        [pscustomobject]@{ Id = 'bcu'; Order = 30; Name = 'Bulk Crap Uninstaller'; Interactive = $true
            Available = 'Test-UdpBcuAvailable'; Plan = 'Get-UdpBcuPlan'; Invoke = 'Invoke-UdpBcu' }
        [pscustomobject]@{ Id = 'browser'; Order = 40; Name = 'Alternative browser'; Interactive = $false
            Available = 'Test-UdpBrowserAvailable'; Plan = 'Get-UdpBrowserPlan'; Invoke = 'Invoke-UdpBrowser' }
        [pscustomobject]@{ Id = 'edge'; Order = 50; Name = 'Edge removal'; Interactive = $false
            Available = 'Test-UdpEdgeRemovalAvailable'; Plan = 'Get-UdpEdgeRemovalPlan'; Invoke = 'Invoke-UdpEdgeRemoval' }
        [pscustomobject]@{ Id = 'nvcleanstall'; Order = 60; Name = 'NVCleanstall'; Interactive = $true
            Available = 'Test-UdpNVCleanstallAvailable'; Plan = 'Get-UdpNVCleanstallPlan'; Invoke = 'Invoke-UdpNVCleanstall' }
        [pscustomobject]@{ Id = 'autoruns'; Order = 70; Name = 'Autoruns'; Interactive = $true
            Available = 'Test-UdpAutorunsAvailable'; Plan = 'Get-UdpAutorunsPlan'; Invoke = 'Invoke-UdpAutoruns' }
    )
}

function New-UdpAvailability {
    param([bool]$Available, [string]$Reason = '')
    return @{ Available = $Available; Reason = $Reason }
}
