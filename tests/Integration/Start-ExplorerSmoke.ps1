[CmdletBinding()]
param([switch]$Run)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ExplorerSmoke.OneClick.Core.ps1')
if ($MyInvocation.InvocationName -eq '.') { return }
$result=Invoke-SmokeOneClick ([bool]$Run) (New-SmokeOneClickAdapter)
ConvertTo-Json -InputObject $result -Depth 24
switch ($result.Status) {
    'Passed' { exit 0 }
    'Failed' { exit 1 }
    'Blocked' { exit 3 }
    default { exit 2 }
}
