# Resume Explorer 0.1.0-beta.1+issue2.instanceguard (beta.2 acceptance pending).
[CmdletBinding()]
param(
    [ValidateSet('Capture','Preview','Restore','PreviewRetry','Retry')][string]$Action = 'Preview',
    [string]$Snapshot = (Join-Path $env:TEMP 'ExplorerTabs-snapshot.json'),
    [string]$ReportPath,
    [int]$GroupIndex,
    [long]$TargetHwnd,
    [int[]]$ItemIndexes,
    [switch]$IncludeUncertain,
    [int]$DetectionTimeoutSeconds = 15,
    [int]$PollIntervalMs = 200,
    [int[]]$TransientErrorBackoffMs = @(200,400,800),
    [int]$StableDurationMs = 600,
    [int]$BaselineTimeoutSeconds = 3,
    [int]$NavigationTimeoutSeconds = 10
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resume-explorer.core.ps1')
$config = @{
    DetectionTimeoutSeconds=$DetectionTimeoutSeconds; PollIntervalMs=$PollIntervalMs
    TransientErrorBackoffMs=$TransientErrorBackoffMs; StableDurationMs=$StableDurationMs
    BaselineTimeoutSeconds=$BaselineTimeoutSeconds; NavigationTimeoutSeconds=$NavigationTimeoutSeconds
}
Assert-RestoreConfig $config
$instanceLock=$null
try {
    $instanceLock=Enter-ResumeExplorerInstanceLock -Path (Get-ResumeExplorerInstanceLockPath)
    switch ($Action) {
        'Capture' { Save-Snapshot $Snapshot }
        'Preview' {
            $data = Read-Snapshot $Snapshot
            $n = 0
            foreach ($g in @($data.Windows)) {
                $n++; Write-Host "Window group $n :"
                foreach ($p in @($g.Paths)) { Write-Host "  [$([IO.Directory]::Exists([string]$p))] $p" }
            }
        }
        'Restore' { Start-RestoreRun -Snapshot $Snapshot -ReportPath $ReportPath -Config $config }
        'PreviewRetry' { Show-RetryPreview -ReportPath $ReportPath }
        'Retry' {
            Start-RetryRun -ReportPath $ReportPath -GroupIndex $GroupIndex -TargetHwnd $TargetHwnd `
                -ItemIndexes $ItemIndexes -IncludeUncertain:$IncludeUncertain -Config $config
        }
    }
} finally {
    # Outermost lifetime includes final checkpoint/summary and Retry's family finally.
    if ($null -ne $instanceLock) { $instanceLock.Dispose() }
}
