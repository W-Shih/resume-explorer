[CmdletBinding()]
param([switch]$Run,[switch]$RequireVisualReview)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ExplorerSmoke.OneClick.Core.ps1')
if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $Run) {
    Invoke-SmokeOneClick $false (New-SmokeOneClickAdapter) | ConvertTo-Json -Depth 24
    exit 2
}
$runId=[guid]::NewGuid().ToString('N')
$engine=(Get-Process -Id $PID).Path
$worker=Join-Path $PSScriptRoot 'Invoke-ExplorerSmoke.OneClickWorker.ps1'
$arguments=@('-NoProfile','-Sta','-File',$worker,'-Run','-RunId',$runId)
if ($RequireVisualReview) { $arguments+='-RequireVisualReview' }
$code=1; $status='程序異常結束／結果不明'
try {
    $rawCode=Invoke-SmokeWorkerProcess $engine $arguments
    $code=if ($rawCode -in @(0,1,2,3)) { $rawCode } else { 1 }
    $status=switch ($rawCode) {
        0 { 'Passed' }; 1 { 'Failed (Exit 1)' }; 2 { 'NotRun／取消或待目視 (Exit 2)' }
        3 { 'Blocked (Exit 3)' }; default { "程序異常結束 (Exit $rawCode)" }
    }
    if ($rawCode -eq 0) {
        $suitePath=Join-Path ([IO.Path]::GetTempPath()) "ResumeExplorer-E2E-Suite-$runId\suite-result.json"
        $suite=Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
        if ($suite.Status -ne 'Passed') { throw 'Worker exited without a Passed suite result' }
        $status='Passed'
    }
} catch {
    $code=1
    if ($_.Exception.Data['WorkerStillRunning']) { $status='測試程序可能仍在執行，請先確認已結束' }
    Write-Warning $_.Exception.Message
}
finally {
    try { Show-SmokeRecovery $runId (Get-SmokeRecoveryBase) $status }
    catch { Write-Warning "復原提示失敗；請查看 BeforeSmoke 目錄：$($_.Exception.Message)" }
}
exit $code
