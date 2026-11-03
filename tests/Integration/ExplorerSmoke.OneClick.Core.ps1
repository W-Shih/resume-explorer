# Guided orchestration over the existing Task-5 harness. Import has no side effects.
. (Join-Path $PSScriptRoot 'ExplorerSmoke.Core.ps1')

function Invoke-SmokeOfflineBaseline {
    $engine=(Get-Process -Id $PID).Path
    $tests=Split-Path $PSScriptRoot -Parent; $rows=@()
    foreach ($suite in @(@{ File='Issue2.Tests.ps1'; Expected=39 },@{ File='RestoreSummary.Tests.ps1'; Expected=17 },
        @{ File='ExplorerSmoke.Tests.ps1'; Expected=21 },@{ File='ExplorerSmoke.OneClick.Tests.ps1'; Expected=14 })) {
        $output=@(& $engine -NoProfile -NonInteractive -File (Join-Path $tests $suite.File) 2>&1)
        $code=$LASTEXITCODE
        $count=@($output | Where-Object { $_.ToString().StartsWith('PASS ') }).Count
        Write-Host "$($suite.File): $count/$($suite.Expected), Exit $code"
        Assert-Smoke ($code -eq 0 -and $count -eq $suite.Expected) ('OfflineBaselineFailed:'+ $suite.File)
        $rows+=[pscustomobject]@{ Suite=$suite.File; Passed=$count; ExitCode=$code }
    }
    return $rows
}

function New-SmokeOneClickAdapter {
    $native=New-SmokeAdapter
    @{
        Native=$native
        Baseline={ Invoke-SmokeOfflineBaseline }
        Harness={ param($options,$adapter) Invoke-ExplorerSmoke $options $adapter }
        Prompt={
            param($kind,$case,$root)
            switch ($kind) {
                'Isolation' {
                    Write-Host 'Use only a resettable Windows 11 VM or dedicated test desktop. Close all Explorer windows there.'
                    Write-Host 'This will create visible Explorer windows/tabs. Never use your working desktop or VDI session.'
                    $choice=Read-Host 'Type VM or TESTACCOUNT to authorize GUI changes in that dedicated environment; Enter cancels'
                    if ($choice -notin @('VM','TESTACCOUNT')) { return $null }
                    $notes=Read-Host 'Identify the actual VM snapshot/test account and exclusive-use approval'
                    if ([string]::IsNullOrWhiteSpace($notes)) { return $null }
                    $environment='DisposableVM'; if ($choice -eq 'TESTACCOUNT') { $environment='DedicatedTestAccount' }
                    return [pscustomobject]@{ Kind=$environment; Notes=$notes }
                }
                'Visual' {
                    Write-Host "Case $case evidence: $root"
                    if ($case -eq 'E01') { Write-Host 'Inspect FOUR visible windows / SIX tabs: original A|B and C, plus restored A|B and C; originals unchanged.' }
                    else { Write-Host 'Inspect ONE visible A|B window: original A unchanged and only B newly added.' }
                    if ((Read-Host 'Type PASS only after actual visual verification; Enter stops without passing') -cne 'PASS') { return $null }
                    $notes=Read-Host 'Record actual observed grouping/ownership and optional screenshot reference'
                    if ([string]::IsNullOrWhiteSpace($notes)) { return $null }
                    return [pscustomobject]@{ Approved=$true; Notes=$notes }
                }
                'Cleanup' {
                    Write-Host "Manually close ONLY the four verified E01 test windows from: $root"
                    Write-Host 'Keep all evidence. Do not close an unknown window; do not restart or kill Explorer.'
                    return ((Read-Host 'Type CONTINUE after all E01 fixture windows are closed; Enter stops') -ceq 'CONTINUE')
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

function Invoke-SmokeOneClick([bool]$Run,$Adapter) {
    $suite=[pscustomobject]@{ Version=1; Status='NotRun'; Reason='NotAuthorized'; E01='NotRun'; E02='NotRun'
        SuiteRoot=$null; E01Root=$null; E02Root=$null; Phase='Consent'; Steps=@(); Baseline=@(); Error=$null }
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
        $root=Join-Path ([IO.Path]::GetTempPath()) ('ResumeExplorer-E2E-Suite-'+[guid]::NewGuid().ToString('N'))
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
            & $save ($case+'-VisualReview') $caseRoot $null
            $review=& $Adapter.Prompt 'Visual' $case $caseRoot
            if ($null -eq $review -or -not $review.Approved -or [string]::IsNullOrWhiteSpace($review.Notes)) {
                $suite.Status='AwaitingVisualReview'; $suite.Reason=$case+'-OperatorReviewPending'; return $suite
            }
            $options.Mode='Confirm'; $options.AllowExplorerUiChanges=$false; $options.ConfirmVisibleAndGrouping=$true; $options.VisualEvidence=$review.Notes
            & $save ($case+'-Confirm') $caseRoot $null
            $confirmed=& $Adapter.Harness $options $Adapter.Native
            $suite.$case=$confirmed.Status
            Assert-Smoke ($confirmed.Status -eq 'Passed') ($case+'-Confirm:'+ $confirmed.Reason)
            if ($case -eq 'E01') {
                & $save 'E01-ManualClose' $caseRoot $null
                if (-not (& $Adapter.Prompt 'Cleanup' $case $caseRoot)) { $suite.Status='NotRun'; $suite.Reason='E02-PendingManualClose'; return $suite }
                $empty=& $Adapter.Native.Observe
                Assert-SmokeScope $empty @() $facts.SessionId
                $options.ConfirmVisibleAndGrouping=$false; $options.VisualEvidence=''
            }
        }
        Assert-Smoke ($suite.E01 -eq 'Passed' -and $suite.E02 -eq 'Passed') 'SuiteNotComplete'
        $suite.Status='Passed'; $suite.Reason='BothCasesObserverAndOperatorVerified'; & $save 'Complete' '' 0
    } catch {
        $suite.Status=$(if ($uiAttempted) { 'Failed' } else { 'Blocked' }); $suite.Reason=$_.Exception.Message
        $suite.Error=[pscustomobject]@{ Message=$_.Exception.Message; HResult=$_.Exception.HResult }
    } finally {
        try { if ($null -ne $save) { & $save $suite.Phase '' $null } }
        finally {
            if ($null -ne $suiteLock) { $suiteLock.Dispose() }
            if ($null -ne $coordinatorLock) { $coordinatorLock.Dispose() }
        }
    }
    return $suite
}
