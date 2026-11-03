# Window lifecycle for the explicitly authorized one-click harness only.
# Import has no native calls. No process termination and no automatic Restore.
function Assert-SmokeClosable($Observation,[int]$SessionId) {
    Assert-Smoke $Observation.Reliable ('ExplorerObservationIncomplete: 無法可靠辨識所有 Explorer 視窗；未關閉未知視窗。請檢查 observation JSON 的 Errors，整理測試桌面後重跑。')
    $views=@($Observation.Views)
    Assert-Smoke (@($views.Identity | Select-Object -Unique).Count -eq $views.Count) 'CloseIdentityAmbiguous: Explorer 分頁身分重複，無法安全關窗；請檢查觀測 JSON 並手動整理測試桌面後重跑。'
    foreach ($view in $views) {
        Assert-Smoke ($view.RootHwnd -gt 0 -and $view.RawHwnd -eq $view.RootHwnd -and
            $view.Fingerprint.RootHwnd -eq $view.RootHwnd -and $view.Fingerprint.Hwnd -eq $view.RawHwnd -and
            $view.Fingerprint.SessionId -eq $SessionId -and $view.Fingerprint.PID -gt 0 -and
            -not [string]::IsNullOrWhiteSpace($view.Fingerprint.ProcessStartedAtUtc) -and
            -not [string]::IsNullOrWhiteSpace($view.Identity) -and -not [string]::IsNullOrWhiteSpace($view.Path)) 'CloseWindowIdentityUnsupported: 無法確認 Explorer 的視窗分組、路徑或目前 session／process 身分；未嘗試關閉，請檢查觀測 JSON 並手動整理測試桌面後重跑。'
    }
}

function Assert-SmokeRemainingScope($Expected,$Now,[int]$SessionId) {
    Assert-SmokeClosable $Now $SessionId
    foreach ($view in @($Now.Views)) {
        $matches=@($Expected.Views | Where-Object { $_.Identity -ceq $view.Identity -and
            $_.RawHwnd -eq $view.RawHwnd -and $_.RootHwnd -eq $view.RootHwnd -and $_.Path -ieq $view.Path -and
            (Test-SmokeFingerprint $_.Fingerprint $view.Fingerprint) })
        Assert-Smoke ($matches.Count -eq 1) 'CloseScopeChanged: 視窗或分頁已改變；已停止，未關閉新出現或身分不符的視窗。'
    }
}

function Close-SmokeWindows($Expected,$Native,[int]$SessionId,[string]$EvidencePrefix) {
    Assert-SmokeClosable $Expected $SessionId
    Write-SmokeJson ($EvidencePrefix+'-before.json') (ConvertTo-SmokeEvidence $Expected) -New
    $actions=@()
    foreach ($group in @($Expected.Views | Group-Object RootHwnd)) {
        # Re-read the whole scope before each close, including paths and run-local COM identity.
        $now=& $Native.Observe
        Write-SmokeJson ($EvidencePrefix+'-after.json') (ConvertTo-SmokeEvidence $now)
        Assert-SmokeRemainingScope $Expected $now $SessionId
        $current=@($now.Views | Where-Object RootHwnd -eq $group.Name)
        if ($current.Count -eq 0) { continue } # Already closed; never resend to a stale handle.
        $action=[pscustomobject]@{ RootHwnd=$current[0].RootHwnd; Fingerprint=$current[0].Fingerprint
            AttemptedAtUtc=[DateTime]::UtcNow.ToString('o'); Posted=$false }
        $actions+=$action
        Write-SmokeJson ($EvidencePrefix+'-actions.json') $actions
        & $Native.CloseWindow $current[0]
        $action.Posted=$true
        Write-SmokeJson ($EvidencePrefix+'-actions.json') $actions
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do {
        $now=& $Native.Observe
        Write-SmokeJson ($EvidencePrefix+'-after.json') (ConvertTo-SmokeEvidence $now)
        Assert-SmokeRemainingScope $Expected $now $SessionId
        if (@($now.Views).Count -eq 0) { return }
        if ($timer.ElapsedMilliseconds -ge 10000) { break }
        & $Native.Wait
    } while ($true)
    throw "ExplorerCloseIncomplete: 仍有 Explorer 視窗，可能正在等待對話框或操作完成。請檢查 $EvidencePrefix-after.json，手動處理後重跑；未終止 Explorer 程序。"
}

function Save-SmokeExistingSnapshot($Observation,$Native,[int]$SessionId,[string]$SuiteRoot) {
    $path=Join-Path $SuiteRoot 'existing-snapshot.json'
    Assert-Smoke (-not (Test-Path -LiteralPath $path)) 'ExistingSnapshotAlreadyExists'
    $code=& $Native.Cli @('-Action','Capture','-Snapshot',$path) (Join-Path $SuiteRoot 'existing-Capture')
    Assert-Smoke ($code -eq 0 -and [IO.File]::Exists($path)) 'ExistingCaptureFailed: 配置儲存失敗；尚未關閉既有視窗，請檢查 existing-Capture 日誌。'
    $snapshot=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $groups=@($Observation.Views | Group-Object RootHwnd | ForEach-Object { @{ Paths=@($_.Group.Path) } })
    try { Assert-SmokeSnapshot $snapshot $groups }
    catch { throw 'ExistingCaptureIncomplete: Snapshot 未完整保存目前的視窗／分頁配置（例如 Home 或其他不支援的路徑）。尚未關閉既有視窗；請檢查 existing-snapshot.json，手動整理後重跑或明確選擇不儲存直接關閉。' }
    $now=& $Native.Observe
    Assert-SmokeRemainingScope $Observation $now $SessionId
    Assert-SmokeOriginalUnchanged $Observation $now
    Write-SmokeJson (Join-Path $SuiteRoot 'existing-snapshot-validation.json') @{
        SHA256=(Get-FileHash -LiteralPath $path).Hash; Observation=(ConvertTo-SmokeEvidence $now) } -New
    Write-Host "已儲存並核對配置：$path（不會自動 Restore）"
    return $path
}
