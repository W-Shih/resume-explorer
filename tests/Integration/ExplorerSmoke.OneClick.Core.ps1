# Guided orchestration over the existing Task-5 harness. Import has no side effects.
. (Join-Path $PSScriptRoot 'ExplorerSmoke.Core.ps1')
. (Join-Path $PSScriptRoot 'ExplorerSmoke.Lifecycle.ps1')
. (Join-Path $PSScriptRoot 'ExplorerSmoke.Recovery.ps1')

function Invoke-SmokeOfflineBaseline {
    $engine=(Get-Process -Id $PID).Path
    $tests=Split-Path $PSScriptRoot -Parent; $rows=@()
    foreach ($suite in @(@{ File='Issue2.Tests.ps1'; Expected=39 },@{ File='RestoreSummary.Tests.ps1'; Expected=17 },
        @{ File='ExplorerSmoke.Tests.ps1'; Expected=23 },@{ File='ExplorerSmoke.OneClick.Tests.ps1'; Expected=49 },
        @{ File='ExplorerSmoke.Recovery.Tests.ps1'; Expected=13 })) {
        $output=@(& $engine -NoProfile -NonInteractive -File (Join-Path $tests $suite.File) 2>&1)
        $code=$LASTEXITCODE
        $count=@($output | Where-Object { $_.ToString().StartsWith('PASS ') }).Count
        Write-Host "$($suite.File): $count/$($suite.Expected), Exit $code"
        Assert-Smoke ($code -eq 0 -and $count -eq $suite.Expected) ('OfflineBaselineFailed:'+ $suite.File)
        $rows+=[pscustomobject]@{ Suite=$suite.File; Passed=$count; ExitCode=$code }
    }
    return $rows
}

function Get-SmokeCloseTarget($Fingerprint) {
    Initialize-SmokeNative
    $handle=[IntPtr]::new($Fingerprint.RootHwnd)
    if (-not [ExplorerSmokeNative]::IsWindow($handle)) { return 'Gone' }
    $root=[ExplorerSmokeNative]::GetAncestor($handle,2).ToInt64()
    [uint32]$processId=0
    [void][ExplorerSmokeNative]::GetWindowThreadProcessId($handle,[ref]$processId)
    if (-not [ExplorerSmokeNative]::IsWindow($handle)) { return 'Gone' }
    if ($root -ne $Fingerprint.RootHwnd -or $processId -ne $Fingerprint.PID) { return 'Changed' }
    $process=Get-Process -Id $processId -ErrorAction Stop
    $current=[pscustomobject]@{ Hwnd=$handle.ToInt64(); RootHwnd=$root; PID=$processId; SessionId=$process.SessionId
        ProcessStartedAtUtc=$process.StartTime.ToUniversalTime().ToString('o') }
    if ($process.ProcessName -ne 'explorer' -or -not (Test-SmokeFingerprint $Fingerprint $current)) { return 'Changed' }
    return 'StillPresent'
}

function Invoke-SmokeWindowClose($View,[scriptblock]$Probe,[scriptblock]$PostOrThrow) {
    # Keep message selection in the tested boundary; transport posts once or throws.
    $status=& $Probe $View.Fingerprint
    if ($status -eq 'Gone') { return 'Gone' }
    Assert-Smoke ($status -eq 'StillPresent') 'CloseFingerprintChanged: 發送關窗要求前視窗身分已改變；未發送，請檢查測試桌面後重跑。'
    # Direct WM_CLOSE can close just the active Explorer tab on Windows 11.
    # Request the window's system-menu Close command (the title-bar close path).
    $null=& $PostOrThrow ([IntPtr]::new($View.RootHwnd)) ([uint32]0x0112) ([IntPtr]::new(0xF060)) ([IntPtr]::Zero)
    return 'Posted'
}

function New-SmokeOneClickAdapter {
    $native=New-SmokeAdapter
    $native.NewCloseClock={ [Diagnostics.Stopwatch]::StartNew() }
    $native.Elapsed={ param($clock) $clock.ElapsedMilliseconds }
    $native.ProbeWindow={ param($fingerprint) Get-SmokeCloseTarget $fingerprint }
    $native.CloseWindow={
        param($view)
        Invoke-SmokeWindowClose $view { param($fp) Get-SmokeCloseTarget $fp } {
            param([IntPtr]$handle,[uint32]$message,[IntPtr]$wparam,[IntPtr]$lparam)
            if (-not [ExplorerSmokeNative]::PostMessage($handle,$message,$wparam,$lparam)) {
                $code=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
                $closeException=[ComponentModel.Win32Exception]::new($code,'CloseMessageFailed: 系統未接受此視窗的關閉要求；未終止程序。')
                $closeException.Data['NativeErrorCode']=$code
                throw $closeException
            }
        }
    }
    $native.Wait={ Start-Sleep -Milliseconds 200 }
    @{
        Native=$native
        Baseline={ Invoke-SmokeOfflineBaseline }
        Harness={ param($options,$adapter) Invoke-ExplorerSmoke $options $adapter }
        Prompt={
            param($kind,$case,$root)
            switch ($kind) {
                'Isolation' {
                    Write-Host '警告：測試會關閉 Explorer 視窗，可能影響目前工作。建議在可重設的 Windows 11 VM 或專用測試桌面執行，以降低干擾工作桌面或 VDI 的風險。'
                    Write-Host '本次授權包含：關閉此桌面既有 Explorer 視窗、建立測試視窗，以及測試通過後自動關閉測試視窗。'
                    Write-Host '不會終止 Explorer 程序；請先完成檔案操作並關閉編輯中的對話框。既有配置可在下一步選擇儲存。'
                    $choice=Read-Host '同意上述操作請輸入 VM 或 TESTACCOUNT；直接 Enter 取消，且不執行測試'
                    if ($choice -notin @('VM','TESTACCOUNT')) { return $null }
                    $notes=Read-Host '[可選 Optional] 環境備註，例如 VM 名稱／快照名稱；電腦、帳號與 session 將自動記錄，Enter 略過'
                    if ([string]::IsNullOrWhiteSpace($notes)) { $notes='Operator authorized exclusive test desktop and window lifecycle; optional environment notes omitted.' }
                    $environment='DisposableVM'; if ($choice -eq 'TESTACCOUNT') { $environment='DedicatedTestAccount' }
                    return [pscustomobject]@{ Kind=$environment; Notes=$notes }
                }
                'Visual' {
                    Write-Host "案例 $case 證據：$root"
                    if ($case -eq 'E01') { $expected='4 個視窗／6 個分頁：原有 A|B 與 C，另有還原的 A|B 與 C；原分頁不變。' }
                    else { $expected='1 個 A|B 視窗：原有 A 不變，只新增一個 B 分頁。' }
                    Write-Host "已選用人工目視模式，請實際檢查：$expected"
                    if ((Read-Host '符合上述條件才輸入 PASS；Enter 停止並保留待驗收狀態，不算人工通過') -cne 'PASS') { return $null }
                    $notes=Read-Host '[可選 Optional] 補充實際觀察或截圖路徑；Enter 略過，僅記錄你確認上述條件'
                    if ([string]::IsNullOrWhiteSpace($notes)) { $notes="Operator visually confirmed: $expected" }
                    return [pscustomobject]@{ Approved=$true; Notes=$notes }
                }
                'ExistingWindows' {
                    Write-Host "偵測到 $($root.Windows) 個既有 Explorer 視窗、$($root.Tabs) 個分頁。測試前需要先關閉。"
                    Write-Host 'S：先儲存 Snapshot JSON，再關閉並測試。C：不儲存，直接關閉並測試。Enter：取消。'
                    Write-Host 'Snapshot 僅保存工具支援的資料夾／分頁配置，不包含檔案操作、選取或捲動位置；測試後不自動還原。'
                    $choice=Read-Host '輸入 S (儲存後關閉) 或 C (直接關閉)；Enter 取消'
                    if ($choice -eq 'S') { return 'Save' }
                    if ($choice -eq 'C') { return 'Close' }
                    return $null
                }
            }
        }
    }
}

function Get-SmokeOneClickLockPath {
    Join-Path ([IO.Path]::GetTempPath()) 'ResumeExplorer-E2E-OneClick.lock'
}

function Initialize-SmokeOneClickE01($Prepared,$Native,$SaveStep) {
    $root=$Prepared.TestRoot; $folder=Join-Path $root 'E01'
    $snapshotPath=Join-Path $folder 'setup-snapshot.json'; $reportPath=Join-Path $folder 'setup-report.json'
    $statePath=Join-Path $root 'smoke-result.json'; $lock=$null; $consumed=$false
    try {
        $null=Assert-SmokeRoot $root $Prepared.Facts E01
        $lock=[IO.File]::Open((Join-Path $root 'smoke-run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        Assert-Smoke ($state.Status -eq 'Prepared' -and -not (Test-Path -LiteralPath $snapshotPath) -and
            -not (Test-Path -LiteralPath $reportPath)) 'SetupReplayOrExistingEvidence'
        $before=& $Native.Observe; Assert-SmokeScope $before @() $Prepared.Facts.SessionId
        $groups=@(@{ Paths=@((Join-Path $folder 'A'),(Join-Path $folder 'B')) },@{ Paths=@((Join-Path $folder 'C')) })
        foreach ($group in $groups) { foreach ($path in $group.Paths) { Assert-Smoke ([IO.Directory]::Exists($path)) 'SetupFolderMissing' } }
        $snapshot=[pscustomobject]@{ Version=1; CapturedAt=[DateTime]::UtcNow.ToString('o'); Windows=$groups }
        Write-SmokeJson $snapshotPath $snapshot -New
        $snapshotHash=(Get-FileHash -LiteralPath $snapshotPath).Hash
        $state.Status='SettingUpFixtures'; $state.Reason='OneClickSetupAttempted-NoReplay'
        Write-SmokeJson $statePath $state; $consumed=$true
        $arguments=@('-Action','Restore','-Snapshot',$snapshotPath,'-ReportPath',$reportPath)
        & $SaveStep 'E01-SetupRestore' $root $null
        $null=Assert-SmokeRoot $root $Prepared.Facts E01
        $latest=& $Native.Observe; Assert-SmokeScope $latest @() $Prepared.Facts.SessionId
        $code=& $Native.Cli $arguments (Join-Path $folder '00-SetupRestore')
        & $SaveStep 'E01-SetupRestoreExit' $root $code
        Assert-Smoke ($code -eq 0) 'SetupCliFailed'
        $report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        Assert-SmokeReport $report $snapshot @('Verified','Verified','Verified')
        Assert-Smoke ($report.SourceSnapshotHash -eq $snapshotHash -and
            (Get-FileHash -LiteralPath $snapshotPath).Hash -eq $snapshotHash) 'SetupSnapshotChanged'
        $after=& $Native.Observe; Assert-SmokeScope $after $groups $Prepared.Facts.SessionId
        foreach ($item in $report.Items) {
            Assert-Smoke (@($after.Views | Where-Object { $_.Path -ieq $item.RequestedPath -and
                (Test-SmokeFingerprint $_.Fingerprint $item.WindowFingerprint) }).Count -eq 1) 'SetupWindowMismatch'
        }
        & $Native.Uia $after.Views # Read-only control probe; no extra Invoke.
        Write-SmokeJson (Join-Path $folder 'setup-observation.json') (ConvertTo-SmokeEvidence $after) -New
        $state.Status='Prepared'; $state.Reason='AutomaticFixtureSetupVerified'
        Write-SmokeJson $statePath $state
    } catch {
        if ($consumed) {
            $state.Status='Failed'; $state.Reason=$_.Exception.Message; $state.E01='Failed'
            Write-SmokeJson $statePath $state
        }
        throw
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}

function Invoke-SmokeOneClick([bool]$Run,$Adapter,[bool]$RequireVisualReview=$false,[string]$RunId='') {
    $suite=[pscustomobject]@{ Version=1; Status='NotRun'; Reason='NotAuthorized'; E01='NotRun'; E02='NotRun'
        SuiteRoot=$null; E01Root=$null; E02Root=$null; Phase='Consent'; Steps=@(); Baseline=@(); Error=$null
        VisualReview=$(if ($RequireVisualReview) { 'Pending' } else { 'NotRun' }); ExistingSnapshot=$null }
    if (-not $Run) { return $suite }
    $save=$null; $suiteLock=$null; $coordinatorLock=$null; $uiAttempted=$false
    try {
        $consent=& $Adapter.Prompt 'Isolation' '' ''
        if ($null -eq $consent -or $consent.Kind -notin @('DisposableVM','DedicatedTestAccount') -or
            [string]::IsNullOrWhiteSpace($consent.Notes)) { $suite.Reason='OperatorDeclinedIsolation'; return $suite }
        $facts=& $Adapter.Native.Facts
        $evidence=[pscustomobject]@{ Kind=$consent.Kind; Dedicated=$true; ComputerName=$facts.ComputerName
            UserSid=$facts.UserSid; SessionId=$facts.SessionId; DesktopName=$facts.DesktopName; Notes=$consent.Notes }
        Assert-SmokeSession $facts $evidence
        Assert-SmokeTempBase ([IO.Path]::GetTempPath())
        $coordinatorLock=[IO.File]::Open((Get-SmokeOneClickLockPath),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if (-not $RunId) { $RunId=[guid]::NewGuid().ToString('N') }
        Assert-Smoke ($RunId -cmatch '^[a-f0-9]{32}$') 'InvalidRecoveryRunId'
        $root=Join-Path ([IO.Path]::GetTempPath()) ('ResumeExplorer-E2E-Suite-'+$RunId)
        Assert-Smoke (-not (Test-Path -LiteralPath $root)) 'SuiteRootAlreadyExists'
        [void][IO.Directory]::CreateDirectory($root); $suite.SuiteRoot=$root
        $suiteLock=[IO.File]::Open((Join-Path $root 'suite.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $evidencePath=Join-Path $root 'session-evidence.json'; Write-SmokeJson $evidencePath $evidence -New
        $writeJson=${function:Write-SmokeJson}
        $save={
            param($phase,$caseRoot,$exitCode)
            $suite.Phase=$phase; $suite.Steps+=[pscustomobject]@{ Phase=$phase; TestRoot=$caseRoot; ExitCode=$exitCode; AtUtc=[DateTime]::UtcNow.ToString('o') }
            & $writeJson (Join-Path $root 'suite-result.json') $suite
        }.GetNewClosure()
        $suite.Status='Running'; & $save 'OfflineBaseline' '' $null
        $suite.Baseline=@(& $Adapter.Baseline)
        & $save 'ExistingWindows' '' $null
        $existing=& $Adapter.Native.Observe
        Write-SmokeJson (Join-Path $root 'existing-observation.json') (ConvertTo-SmokeEvidence $existing) -New
        Assert-SmokeClosable $existing $facts.SessionId
        if (@($existing.Views).Count -gt 0) {
            $choice=& $Adapter.Prompt 'ExistingWindows' '' @{
                Windows=@($existing.Views | Group-Object RootHwnd).Count; Tabs=@($existing.Views).Count }
            if ($choice -notin @('Save','Close')) { $suite.Status='NotRun'; $suite.Reason='ExistingWindows-OperatorCancelled'; return $suite }
            if ($choice -eq 'Save') {
                & $save 'ExistingSnapshot' '' $null
                $suite.ExistingSnapshot=Save-SmokeExistingSnapshot $existing $Adapter.Native $facts.SessionId $root
            }
            & $save 'ExistingWindowsClose' '' $null
            $uiAttempted=$true
            Close-SmokeWindows $existing $Adapter.Native $facts.SessionId (Join-Path $root 'existing-close')
        }
        $options=@{ Mode='Preflight'; Case='E01'; ConfirmIsolatedSession=$true; SessionEvidence=$evidencePath
            AllowExplorerUiChanges=$false; TestRoot=''; ConfirmVisibleAndGrouping=$false; VisualEvidence='' }
        & $save 'Preflight' '' $null
        $preflight=& $Adapter.Harness $options $Adapter.Native
        Assert-Smoke ($preflight.Status -eq 'Ready') ('Preflight:'+ $preflight.Reason)
        foreach ($case in @('E01','E02')) {
            $options.Mode='Prepare'; $options.Case=$case; $options.TestRoot=''; $options.AllowExplorerUiChanges=$false
            & $save ($case+'-Prepare') '' $null
            $prepared=& $Adapter.Harness $options $Adapter.Native
            Assert-Smoke ($prepared.Status -eq 'Prepared') ($case+'-Prepare:'+ $prepared.Reason)
            $caseRoot=$prepared.TestRoot; $suite.($case+'Root')=$caseRoot
            if ($case -eq 'E01') {
                $uiAttempted=$true; & $save 'E01-Setup' $caseRoot $null
                Initialize-SmokeOneClickE01 $prepared $Adapter.Native $save
            }
            $options.Mode='Run'; $options.TestRoot=$caseRoot; $options.AllowExplorerUiChanges=$true
            $uiAttempted=$true; & $save ($case+'-Run') $caseRoot $null
            $result=& $Adapter.Harness $options $Adapter.Native
            $suite.$case=$result.Status
            Assert-Smoke ($result.Status -eq 'AwaitingVisualReview') ($case+'-Run:'+ $result.Reason)
            $options.Mode='Verify'; $options.AllowExplorerUiChanges=$false
            $options.ConfirmVisibleAndGrouping=$false; $options.VisualEvidence=''
            if ($RequireVisualReview) {
                & $save ($case+'-VisualReview') $caseRoot $null
                $review=& $Adapter.Prompt 'Visual' $case $caseRoot
                if ($null -eq $review -or -not $review.Approved -or [string]::IsNullOrWhiteSpace($review.Notes)) {
                    $suite.Status='AwaitingVisualReview'; $suite.Reason=$case+'-OperatorReviewPending'; return $suite
                }
                $options.Mode='Confirm'; $options.ConfirmVisibleAndGrouping=$true; $options.VisualEvidence=$review.Notes
            }
            & $save ($case+'-'+$options.Mode) $caseRoot $null
            $confirmed=& $Adapter.Harness $options $Adapter.Native
            $suite.$case=$confirmed.Status
            Assert-Smoke ($confirmed.Status -eq 'Passed') ($case+'-'+$options.Mode+':'+ $confirmed.Reason)
            # The independent verified observation defines exactly which windows may be closed.
            $expected=$confirmed.After
            Assert-Smoke ($null -ne $expected -and @($expected.Views).Count -gt 0) 'CleanupEvidenceMissing'
            $null=Assert-SmokeRoot $caseRoot $facts $case
            foreach ($view in $expected.Views) {
                $folderPrefix=(Join-Path $caseRoot $case)+[IO.Path]::DirectorySeparatorChar
                Assert-Smoke ($view.Path.StartsWith($folderPrefix,[StringComparison]::OrdinalIgnoreCase)) 'CleanupPathOutsideFixture'
            }
            & $save ($case+'-AutomaticClose') $caseRoot $null
            $live=Get-SmokeCleanupBaseline $expected $Adapter.Native $facts.SessionId (Join-Path $root ($case+'-close-handoff.json'))
            $expected=$live # Strong RCW references, not persisted IUnknown pointer strings.
            Close-SmokeWindows $expected $Adapter.Native $facts.SessionId (Join-Path $root ($case+'-close'))
            $options.ConfirmVisibleAndGrouping=$false; $options.VisualEvidence=''
        }
        Assert-Smoke ($suite.E01 -eq 'Passed' -and $suite.E02 -eq 'Passed') 'SuiteNotComplete'
        $suite.Status='Passed'; $suite.Reason='BothCasesIndependentObserverVerified-VisualReviewNotRun'
        if ($RequireVisualReview) { $suite.VisualReview='Passed'; $suite.Reason='BothCasesObserverAndOperatorVerified' }
        & $save 'Complete' '' 0
    } catch {
        $suite.Status=$(if ($uiAttempted) { 'Failed' } else { 'Blocked' }); $suite.Reason=$_.Exception.Message
        $suite.Error=[pscustomobject]@{ Message=$_.Exception.Message; HResult=$_.Exception.HResult
            CloseSummary=$_.Exception.Data['CloseSummary']; NativeErrorCode=$_.Exception.Data['NativeErrorCode']
            CloseEvidenceWriteError=$_.Exception.Data['CloseEvidenceWriteError']; ExistingSnapshot=$suite.ExistingSnapshot }
    } finally {
        try { if ($null -ne $save) { & $save $suite.Phase '' $null } }
        finally {
            if ($null -ne $suiteLock) { $suiteLock.Dispose() }
            if ($null -ne $coordinatorLock) { $coordinatorLock.Dispose() }
        }
    }
    return $suite
}
