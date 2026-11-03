[CmdletBinding()]
param(
    [ValidateSet('Preflight','Prepare','Run','Confirm')][string]$Mode='Preflight',
    [ValidateSet('E01','E02')][string]$Case='E01',
    [switch]$AllowExplorerUiChanges,
    [switch]$ConfirmIsolatedSession,
    [string]$SessionEvidence,
    [string]$TestRoot,
    [switch]$ConfirmVisibleAndGrouping,
    [string]$VisualEvidence
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ExplorerSmoke.Core.ps1')
if ($MyInvocation.InvocationName -eq '.') { return } # Import never observes Explorer or runs a case.
$options=@{ Mode=$Mode; Case=$Case; AllowExplorerUiChanges=[bool]$AllowExplorerUiChanges
    ConfirmIsolatedSession=[bool]$ConfirmIsolatedSession; SessionEvidence=$SessionEvidence; TestRoot=$TestRoot
    ConfirmVisibleAndGrouping=[bool]$ConfirmVisibleAndGrouping; VisualEvidence=$VisualEvidence }
$result=Invoke-ExplorerSmoke $options (New-SmokeAdapter)
ConvertTo-Json -InputObject $result -Depth 24
switch ($result.Status) {
    'Passed' { exit 0 }
    'Failed' { exit 1 }
    'Blocked' { exit 3 }
    default { exit 2 } # NotRun / Ready / Prepared / AwaitingVisualReview are never E2E success.
}
