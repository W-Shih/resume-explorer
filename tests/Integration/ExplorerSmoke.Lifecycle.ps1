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
    Assert-SmokeCloseKnownViews $Expected $Now
}

function Assert-SmokeCloseKnownViews($Expected,$Now) {
    foreach ($view in @($Now.Views)) {
        $matches=@($Expected.Views | Where-Object { $_.Identity -ceq $view.Identity -and
            $_.RawHwnd -eq $view.RawHwnd -and $_.RootHwnd -eq $view.RootHwnd -and $_.Path -ieq $view.Path -and
            (Test-SmokeFingerprint $_.Fingerprint $view.Fingerprint) })
        Assert-Smoke ($matches.Count -eq 1) 'CloseScopeChanged: 視窗或分頁已改變；已停止，未關閉新出現或身分不符的視窗。'
    }
}

function Write-SmokeCloseTrace($Context,[string]$Event,$Detail) {
    # Bounded independently of clocks/adapters; after.json and actions.json retain final state.
    if ($Context.TraceCount -ge 256) { return }
    $row=[pscustomobject]@{ Sequence=$Context.TraceCount; Event=$Event
        ElapsedMs=(& $Context.Native.Elapsed $Context.Clock); AtUtc=[DateTime]::UtcNow.ToString('o'); Detail=$Detail }
    $json=ConvertTo-Json -InputObject $row -Depth 24 -Compress
    [IO.File]::AppendAllText($Context.Prefix+'-observations.jsonl',$json+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $Context.TraceCount++
}

function Assert-SmokeCloseBudget($Context) {
    if ((& $Context.Native.Elapsed $Context.Clock) -lt 10000) { return }
    foreach ($entry in $Context.Ledger) { if ($entry.State -eq 'Posted') { $entry.State='TimedOut' } }
    if ($Context.Ready -and @($Context.Now.Views).Count -gt 0) {
        throw 'ExplorerCloseIncomplete: 共用 10 秒預算已用盡，仍有原始 Explorer 視窗未消失；不會重新發送或終止程序。'
    }
    throw 'CloseObservationTimedOut: 共用 10 秒預算已用盡，尚未取得穩定且完整的 Explorer 觀測；未繼續關閉其他視窗。'
}

function Get-SmokeCloseSample($Context) {
    Assert-SmokeCloseBudget $Context
    try { $now=& $Context.Native.Observe }
    catch {
        $now=[pscustomobject]@{ Reliable=$false; Views=@(); Errors=@([pscustomobject]@{
            Stage='Observe'; Message=$_.Exception.Message; HResult=$_.Exception.HResult }) }
    }
    if ($null -eq $now) { $now=[pscustomobject]@{ Reliable=$false; Views=@(); Errors=@(@{ Stage='Observe'; Message='NoObservation' }) } }
    $probes=@(foreach ($entry in $Context.Ledger) {
        try {
            $status=& $Context.Native.ProbeWindow $entry.Fingerprint
            Assert-Smoke ($status -in @('Gone','StillPresent','Changed')) 'CloseProbeInvalidResult'
            [pscustomobject]@{ RootHwnd=$entry.RootHwnd; Status=$status; Error=$null }
        } catch {
            [pscustomobject]@{ RootHwnd=$entry.RootHwnd; Status='Unknown'; Error=[pscustomobject]@{
                Message=$_.Exception.Message; HResult=$_.Exception.HResult } }
        }
    })
    foreach ($probe in $probes) {
        $entry=@($Context.Ledger | Where-Object RootHwnd -eq $probe.RootHwnd)[0]
        $entry.LastObservedAtUtc=[DateTime]::UtcNow.ToString('o')
        $entry.LastProbeStatus=$probe.Status; $entry.LastProbeError=$probe.Error
    }
    $Context.Now=$now; $Context.Probes=$probes; $Context.Ready=$false
    Write-SmokeJson ($Context.Prefix+'-after.json') (ConvertTo-SmokeEvidence $now)
    Write-SmokeCloseTrace $Context 'Observe' @{ Observation=(ConvertTo-SmokeEvidence $now); Probes=$probes }
    # Positive contradictions are terminal even in incomplete samples; absence is never proof.
    Assert-SmokeCloseKnownViews $Context.Expected $now
    foreach ($root in @($now.Win32Roots)) {
        if ($null -ne $root) { Assert-Smoke ($root -in @($Context.Ledger.RootHwnd)) 'CloseScopeChanged: 偵測到未授權的 Win32 Explorer 視窗；停止關窗。' }
    }
    Assert-Smoke (@($probes | Where-Object Status -eq 'Changed').Count -eq 0) 'CloseFingerprintChanged: 原 HWND 已被重用或 process／session 身分改變；停止關窗。'
    $ready=$now.Reliable -and @($probes | Where-Object Status -eq 'Unknown').Count -eq 0
    if ($now.Reliable) { Assert-SmokeRemainingScope $Context.Expected $now $Context.SessionId }
    foreach ($probe in $probes) {
        $present=$probe.RootHwnd -in @($now.Views.RootHwnd)
        if (($probe.Status -eq 'Gone' -and $present) -or ($probe.Status -eq 'StillPresent' -and -not $present)) { $ready=$false }
    }
    if ($ready) {
        foreach ($entry in $Context.Ledger) {
            if ($entry.State -ne 'Planned' -or $entry.RootHwnd -notin @($now.Views.RootHwnd)) { continue }
            # An unsent window cannot lose tabs silently; whole-window disappearance is allowed.
            $old=[pscustomobject]@{ Views=@($Context.Expected.Views | Where-Object RootHwnd -eq $entry.RootHwnd) }
            Assert-SmokeOriginalUnchanged $old $now
        }
    }
    $key=ConvertTo-Json -InputObject @($now.Views | Sort-Object RootHwnd,Identity |
        Select-Object Identity,RawHwnd,RootHwnd,Path,Fingerprint) -Depth 10 -Compress
    $elapsed=[long](& $Context.Native.Elapsed $Context.Clock)
    $Context.StableCount=$(if ($ready -and $Context.PreviousReady -and $key -ceq $Context.PreviousKey -and
        $elapsed-$Context.PreviousAt -ge 200) { $Context.StableCount+1 } elseif ($ready) { 1 } else { 0 })
    $Context.PreviousReady=$ready; $Context.PreviousKey=$key; $Context.PreviousAt=$elapsed; $Context.Ready=$ready
    Assert-SmokeCloseBudget $Context
}

function Wait-SmokeCloseSample($Context) {
    Assert-SmokeCloseBudget $Context
    & $Context.Native.Wait
    Get-SmokeCloseSample $Context
}

function Close-SmokeWindows($Expected,$Native,[int]$SessionId,[string]$EvidencePrefix) {
    Assert-SmokeClosable $Expected $SessionId
    $context=@{ Expected=$Expected; Native=$Native; SessionId=$SessionId; Prefix=$EvidencePrefix
        Clock=(& $Native.NewCloseClock); Ledger=@(); TraceCount=0; Ready=$false; Now=$null; Probes=@()
        PreviousReady=$false; PreviousKey=''; PreviousAt=0; StableCount=0; Started=$false }
    $context.Ledger=@(foreach ($group in @($Expected.Views | Group-Object RootHwnd)) {
        [pscustomobject]@{ RootHwnd=$group.Group[0].RootHwnd; Fingerprint=$group.Group[0].Fingerprint
            Views=@($group.Group | Select-Object Identity,RawHwnd,RootHwnd,Path,Fingerprint)
            State='Planned'; AttemptedAtUtc=$null; Posted=$false; LastObservedAtUtc=$null
            LastProbeStatus=$null; LastProbeError=$null }
    })
    # Existing files reject replay before any window action. All persistence errors stop progress.
    Write-SmokeJson ($EvidencePrefix+'-before.json') (ConvertTo-SmokeEvidence $Expected) -New
    $stream=[IO.File]::Open($EvidencePrefix+'-observations.jsonl',[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $stream.Dispose()
    try {
        Write-SmokeJson ($EvidencePrefix+'-actions.json') $context.Ledger -New
        Get-SmokeCloseSample $context
        Assert-Smoke $context.Ready 'ExplorerObservationIncomplete: 第一個關窗要求前觀測已不可靠；未開始關窗。'
        foreach ($entry in $context.Ledger) {
            Get-SmokeCloseSample $context # Refresh scope before every target.
            while (-not $context.Ready) {
                Assert-Smoke $context.Started 'ExplorerObservationIncomplete: 尚未開始關窗且觀測不可靠；停止。'
                Wait-SmokeCloseSample $context
            }
            $probe=@($context.Probes | Where-Object RootHwnd -eq $entry.RootHwnd)[0]
            if ($probe.Status -ne 'Gone') {
                $entry.State='Posting'; $entry.AttemptedAtUtc=[DateTime]::UtcNow.ToString('o')
                Write-SmokeJson ($EvidencePrefix+'-actions.json') $context.Ledger
                Write-SmokeCloseTrace $context 'Posting' @{ RootHwnd=$entry.RootHwnd }
                Assert-SmokeCloseBudget $context
                $view=@($context.Now.Views | Where-Object RootHwnd -eq $entry.RootHwnd)[0]
                $context.Started=$true
                $result=& $Native.CloseWindow $view # Adapter probes once more immediately before posting.
                Assert-Smoke ($result -in @('Posted','Gone')) 'CloseSendInvalidResult'
                if ($result -eq 'Posted') { $entry.Posted=$true; $entry.State='Posted' }
                Write-SmokeJson ($EvidencePrefix+'-actions.json') $context.Ledger
                Write-SmokeCloseTrace $context $result @{ RootHwnd=$entry.RootHwnd }
                Get-SmokeCloseSample $context
            }
            while (-not ($context.Ready -and $context.StableCount -ge 2 -and
                @($context.Probes | Where-Object { $_.RootHwnd -eq $entry.RootHwnd -and $_.Status -eq 'Gone' }).Count -eq 1)) {
                Wait-SmokeCloseSample $context
            }
            # Neither Closed nor AlreadyGone is terminal until coherent disappearance is stable.
            $entry.State=$(if ($entry.Posted) { 'Closed' } else { 'AlreadyGone' })
            $entry.LastObservedAtUtc=[DateTime]::UtcNow.ToString('o')
            Write-SmokeJson ($EvidencePrefix+'-actions.json') $context.Ledger
            Write-SmokeCloseTrace $context $entry.State @{ RootHwnd=$entry.RootHwnd }
        }
        while (-not ($context.Ready -and $context.StableCount -ge 2 -and @($context.Now.Views).Count -eq 0)) {
            Wait-SmokeCloseSample $context
        }
        Write-SmokeCloseTrace $context 'Complete' @{ Targets=$context.Ledger.Count }
    } catch {
        $original=$_.Exception
        foreach ($entry in $context.Ledger) { if ($entry.State -in @('Posting','Posted')) { $entry.State='Failed' } }
        $closed=@($context.Ledger | Where-Object State -in @('Closed','AlreadyGone')).Count
        $unsent=@($context.Ledger | Where-Object { $_.State -notin @('Closed','AlreadyGone') -and $null -eq $_.AttemptedAtUtc }).Count
        $original.Data['CloseSummary']="原定 $($context.Ledger.Count) 個視窗；已確認消失 $closed 個，尚未嘗試投遞 $unsent 個。紀錄：$EvidencePrefix-actions.json；$EvidencePrefix-observations.jsonl"
        try {
            Write-SmokeJson ($EvidencePrefix+'-actions.json') $context.Ledger
            Write-SmokeCloseTrace $context 'Failed' @{ Message=$original.Message; HResult=$original.HResult
                NativeErrorCode=$original.Data['NativeErrorCode']; Summary=$original.Data['CloseSummary'] }
        } catch { $original.Data['CloseEvidenceWriteError']=$_.Exception.Message }
        throw $original
    }
}

function Save-SmokeExistingSnapshot($Observation,$Native,[int]$SessionId,[string]$SuiteRoot) {
    $path=Join-Path $SuiteRoot 'existing-snapshot.json'
    Assert-Smoke (-not (Test-Path -LiteralPath $path)) 'ExistingSnapshotAlreadyExists'
    $code=& $Native.Cli @('-Action','Capture','-Snapshot',$path) (Join-Path $SuiteRoot 'existing-Capture')
    Assert-Smoke ($code -eq 0 -and [IO.File]::Exists($path)) 'ExistingCaptureFailed: 配置儲存失敗；尚未關閉既有視窗，請檢查 existing-Capture 日誌。'
    $snapshotBytes=[IO.File]::ReadAllBytes($path)
    $snapshot=[Text.Encoding]::UTF8.GetString($snapshotBytes) | ConvertFrom-Json
    $hasher=[Security.Cryptography.SHA256]::Create()
    try { $validatedHash=[BitConverter]::ToString($hasher.ComputeHash($snapshotBytes)).Replace('-','') }
    finally { $hasher.Dispose() }
    $groups=@($Observation.Views | Group-Object RootHwnd | ForEach-Object { @{ Paths=@($_.Group.Path) } })
    try { Assert-SmokeSnapshot $snapshot $groups }
    catch { throw 'ExistingCaptureIncomplete: Snapshot 未完整保存目前的視窗／分頁配置（例如 Home 或其他不支援的路徑）。尚未關閉既有視窗；請檢查 existing-snapshot.json，手動整理後重跑或明確選擇不儲存直接關閉。' }
    $now=& $Native.Observe
    Assert-SmokeRemainingScope $Observation $now $SessionId
    Assert-SmokeOriginalUnchanged $Observation $now
    Write-SmokeJson (Join-Path $SuiteRoot 'existing-snapshot-validation.json') @{
        SHA256=$validatedHash; Observation=(ConvertTo-SmokeEvidence $now) } -New
    $base=if ($Native.RecoveryBase) { & $Native.RecoveryBase } else { Get-SmokeRecoveryBase }
    return Publish-SmokeRecovery $path $SuiteRoot $base $validatedHash
}
