# Test-only seam: copy the unchanged public CLI, replace only its core dependency.
# Caller owns Directory and its cleanup. No production lock path is ever opened.
function New-IsolatedTestCli([string]$Directory,[string]$CoreOverrides='',[string]$Anchor='') {
    $root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if (-not [IO.Directory]::Exists($Directory)) { throw 'Fixture directory must already exist.' }
    if (-not $Anchor) { $Anchor=Join-Path $Directory 'instance.lock' }
    $entry=Join-Path $Directory 'resume-explorer.ps1'
    Copy-Item -LiteralPath (Join-Path $root 'resume-explorer.ps1') -Destination $entry
    $core=(Join-Path $root 'resume-explorer.core.ps1').Replace("'","''")
    $quotedAnchor=$Anchor.Replace("'","''")
    $shim=". '$core'`nfunction Get-ResumeExplorerInstanceLockPath { '$quotedAnchor' }`n"+$CoreOverrides
    [IO.File]::WriteAllText((Join-Path $Directory 'resume-explorer.core.ps1'),$shim,[Text.UTF8Encoding]::new($false))
    $entry
}
