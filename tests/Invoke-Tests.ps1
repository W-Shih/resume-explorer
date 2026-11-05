# Public offline entry. Dot-source is safe and does not execute the manifest.
. (Join-Path $PSScriptRoot 'TestRunner.Core.ps1')
function Invoke-OfflineTests {
    $result=Invoke-OfflineTestRun
    foreach ($row in $result.Run.Suites) {
        Write-Host "$($row.Name): $($row.ObservedPassed)/$($row.Expected), Exit $($row.RawExitCode), $($row.Status)"
    }
    Write-Host "Offline: $($result.Run.OverallStatus); E2E: NotRun (OfflineOnly)"
    $result
}
if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference='Stop'
    try { $result=Invoke-OfflineTests; exit $result.ExitCode }
    catch { Write-Host "Offline runner error: $_"; exit 2 }
}
