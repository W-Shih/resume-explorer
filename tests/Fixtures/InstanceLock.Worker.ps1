# Only used by InstanceLock.Tests.ps1 with an explicit owned fixture anchor.
param([string]$Core,[string]$Anchor,[ValidateSet('Hold','Try','Race')][string]$Mode,
    [string]$Ready,[string]$Release,[string]$Gate,[string]$Acquired)
$ErrorActionPreference='Stop'
. $Core
function Wait-Signal([string]$Path) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($Path)) {
        if ($clock.Elapsed.TotalSeconds -gt 30) { throw "WorkerSignalTimeout: $Path" }
        Start-Sleep -Milliseconds 20
    }
}
function Publish-Pid([string]$Path) {
    [IO.File]::WriteAllText(($Path+'.partial'),[string]$PID)
    [IO.File]::Move(($Path+'.partial'),$Path)
}
$handle=$null
try {
    if ($Mode -eq 'Race') { Publish-Pid $Ready; Wait-Signal $Gate }
    $handle=Enter-ResumeExplorerInstanceLock $Anchor
    Write-Host "Acquired:$PID"
    if ($Mode -eq 'Hold') { Publish-Pid $Ready; Wait-Signal $Release }
    if ($Mode -eq 'Race') { Publish-Pid $Acquired; Wait-Signal $Release }
} finally { if ($null -ne $handle) { $handle.Dispose() } }
