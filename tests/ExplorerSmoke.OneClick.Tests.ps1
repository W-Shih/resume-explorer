# Offline wizard tests. Every apparent GUI/CLI operation below is synthetic.
# Their results are never live E01/E02 acceptance evidence.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Integration\ExplorerSmoke.OneClick.Core.ps1')
$script:passed=0
function Assert($Condition,$Message='Assertion failed') { if (-not $Condition) { throw $Message } }
function Test($Name,[scriptblock]$Body) { & $Body; $script:passed++; Write-Host "PASS $Name" }
$script:storage=Join-Path $env:TEMP ('SmokeWizardTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:storage)
$script:owned=New-Object System.Collections.ArrayList
# Unit tests use their own cooperative lock, never a real launcher's coordinator lock.
function Get-SmokeOneClickLockPath { Join-Path $script:storage 'coordinator.lock' }

function New-WizardFixture {
    $state=@{ Calls=@(); Views=@(); Consent=$true; Review=$true; Cleanup=$true; KeepWindows=$false
        SetupExit=0; SetupUnverified=$false; RunFailed=$false; BaselineFailed=$false; FactsReads=0; CliCalls=0
        ExistingChoice='Close'; CaptureExit=0; CaptureMismatch=$false; Closes=@(); Reliable=$true; Elapsed=0
        TransientCase=''; PermanentCase=''; BadSamples=0 }
    $facts=[pscustomobject]@{ Windows=$true; Build=22631; Edition='Core'; Major=7; Version='Synthetic'; Apartment='STA'
        Interactive=$true; SessionId=10; ComputerName='SYNTHETIC-VM'; UserSid='SYNTHETIC-SID'
        DesktopAccessible=$true; DesktopName='Default'; CurrentDesktopName='Default' }
    $write=${function:Write-SmokeJson}; $invokeHarness=${function:Invoke-ExplorerSmoke}; $owned=$script:owned
    $native=@{
        Facts={ $state.FactsReads++; $facts }.GetNewClosure()
        Observe={
            $bad=$state.BadSamples -gt 0; if ($bad) { $state.BadSamples-- }
            [pscustomobject]@{ Reliable=($state.Reliable -and -not $bad); Views=@($state.Views)
                Errors=@(if ($bad) { @{ Message='SyntheticClosingTransition'; HResult=9 } }); ObservedAtUtc='synthetic'; ForegroundHwnd=0 }
        }.GetNewClosure()
        Uia={ param($views) $state.Calls+='Uia' }.GetNewClosure()
        NewCloseClock={ [pscustomobject]@{ Start=$state.Elapsed } }.GetNewClosure()
        Elapsed={ param($clock) $state.Elapsed-$clock.Start }.GetNewClosure()
        ProbeWindow={ param($fp) if ($fp.RootHwnd -in @($state.Views.RootHwnd)) { 'StillPresent' } else { 'Gone' } }.GetNewClosure()
        CloseWindow={
            param($view)
            if (-not $state.Cleanup) { throw 'SyntheticCloseRejected' }
            $state.Closes+=$view.RootHwnd; $state.Calls+='CloseWindow'
            if (-not $state.KeepWindows) { $state.Views=@($state.Views | Where-Object RootHwnd -ne $view.RootHwnd) }
            $stage='Existing'; if ($view.Path -match '[\\/]E01[\\/]') { $stage='E01' } elseif ($view.Path -match '[\\/]E02[\\/]') { $stage='E02' }
            if ($stage -eq $state.TransientCase) { $state.BadSamples=2 }
            if ($stage -eq $state.PermanentCase) { $state.BadSamples=1000 }
            return 'Posted'
        }.GetNewClosure()
        Wait={ if ($state.KeepWindows) { throw 'SyntheticCloseStillPending' }; $state.Elapsed+=200 }.GetNewClosure()
        Cli={
            param($arguments,$prefix)
            $state.CliCalls++
            if ($arguments[1] -eq 'Capture') {
                $state.Calls+='ExistingCapture'
                if ($state.CaptureExit -ne 0) { return $state.CaptureExit }
                $groups=@($state.Views | Group-Object RootHwnd | ForEach-Object { @{ Paths=@($_.Group.Path) } })
                if ($state.CaptureMismatch) { $groups=@() }
                & $write $arguments[3] @{ Version=1; Windows=$groups } -New
                return 0
            }
            $state.Calls+='SetupRestore'
            if ($arguments[1] -ne 'Restore' -or $arguments[2] -ne '-Snapshot' -or $arguments[4] -ne '-ReportPath') { throw 'Wrong setup CLI arguments' }
            if ($arguments[5] -ne (Join-Path ([IO.Path]::GetDirectoryName($arguments[3])) 'setup-report.json')) { throw 'Unexpected report path' }
            if ($state.SetupExit -ne 0) { return $state.SetupExit }
            $snapshot=Get-Content -LiteralPath $arguments[3] -Raw | ConvertFrom-Json
            $items=@(); $views=@(); $g=0
            foreach ($group in $snapshot.Windows) {
                $g++; $i=0; $hwnd=10*$g
                $fp=[pscustomobject]@{ Hwnd=$hwnd; RootHwnd=$hwnd; PID=42; SessionId=10; ProcessStartedAtUtc='2026-11-02T00:00:00Z' }
                foreach ($path in $group.Paths) {
                    $i++; $status='Verified'; if ($state.SetupUnverified) { $status='OutcomeUnknown' }
                    $items+=[pscustomobject]@{ GroupIndex=$g; ItemIndex=$i; RequestedPath=$path; Status=$status; WindowFingerprint=$fp }
                    $views+=[pscustomobject]@{ Identity="$g-$i"; RawHwnd=$hwnd; RootHwnd=$hwnd; Path=$path; Visible=$true; Fingerprint=$fp }
                }
            }
            $report=[pscustomobject]@{ SchemaVersion=1; State='Completed'; SourceSnapshotHash=(Get-FileHash -LiteralPath $arguments[3]).Hash; Items=$items }
            & $write $arguments[5] $report -New
            $state.Views=$views
            return 0
        }.GetNewClosure()
    }
    $adapter=@{
        Native=$native
        Baseline={ $state.Calls+='Baseline'; if ($state.BaselineFailed) { throw 'SyntheticBaselineFailed' }; [pscustomobject]@{ Suite='synthetic'; ExitCode=0 } }.GetNewClosure()
        Prompt={
            param($kind,$case,$root)
            $state.Calls+=($kind+':'+$case)
            if ($kind -eq 'Isolation') {
                if (-not $state.Consent) { return $null }
                return [pscustomobject]@{ Kind='DisposableVM'; Notes='OFFLINE SYNTHETIC ONLY, not a live environment approval' }
            }
            if ($kind -eq 'Visual') {
                if (-not $state.Review) { return $null }
                return [pscustomobject]@{ Approved=$true; Notes='OFFLINE simulated review, not real GUI evidence' }
            }
            if ($kind -eq 'ExistingWindows') { return $state.ExistingChoice }
        }.GetNewClosure()
        Harness={
            param($options,$native)
            $state.Calls+=($options.Mode+':'+$options.Case)
            if ($options.Mode -in @('Preflight','Prepare')) {
                $result=& $invokeHarness $options $native
                if ($result.TestRoot) { [void]$owned.Add($result.TestRoot) }
                return $result
            }
            if ($options.Mode -eq 'Run') {
                if (-not $options.AllowExplorerUiChanges) { throw 'GUI opt-in missing' }
                if ($state.RunFailed) { return [pscustomobject]@{ Status='Failed'; Reason='SyntheticCaseFailure' } }
                if ($options.Case -eq 'E01') {
                    $restored=@(foreach ($v in $state.Views) {
                        $copy=$v | Select-Object *; $copy.Identity='new-'+$v.Identity
                        $copy.RootHwnd+=100; $copy.RawHwnd+=100
                        $copy.Fingerprint=$v.Fingerprint | Select-Object *
                        $copy.Fingerprint.RootHwnd+=100; $copy.Fingerprint.Hwnd+=100; $copy
                    })
                    $state.Views=@($state.Views)+$restored
                } else {
                    $fp=[pscustomobject]@{ Hwnd=50; RootHwnd=50; PID=42; SessionId=10; ProcessStartedAtUtc='2026-11-02T00:00:00Z' }
                    $state.Views=@(foreach ($name in @('A','B')) {
                        [pscustomobject]@{ Identity=$name; RawHwnd=50; RootHwnd=50; Path=(Join-Path $options.TestRoot "E02\$name"); Visible=$true; Fingerprint=$fp }
                    })
                }
                return [pscustomobject]@{ Status='AwaitingVisualReview' }
            }
            if ($options.Mode -eq 'Confirm' -and (-not $options.ConfirmVisibleAndGrouping -or [string]::IsNullOrWhiteSpace($options.VisualEvidence))) { throw 'Missing manual review' }
            if ($options.Mode -notin @('Confirm','Verify')) { throw 'Unexpected verification mode' }
            [pscustomobject]@{ Status='Passed'; After=(& $native.Observe) } # Synthetic routing only, not live evidence.
        }.GetNewClosure()
    }
    @{ State=$state; Facts=$facts; Adapter=$adapter }
}
function Remember-WizardSuite($Result) { if ($Result.SuiteRoot) { [void]$script:owned.Add($Result.SuiteRoot) } }
function New-WizardExistingView {
    [pscustomobject]@{ Identity='existing'; RawHwnd=90; RootHwnd=90; Path='C:\existing'; Visible=$true
        Fingerprint=[pscustomobject]@{ Hwnd=90; RootHwnd=90; PID=42; SessionId=10; ProcessStartedAtUtc='2026-11-02T00:00:00Z' } }
}
function New-CloseFixture([int[]]$Roots=@(10,20)) {
    $views=@(foreach ($n in $Roots) {
        $v=New-WizardExistingView; $v.Identity="view-$n"; $v.RootHwnd=$n; $v.RawHwnd=$n
        $v.Fingerprint.Hwnd=$n; $v.Fingerprint.RootHwnd=$n; $v
    })
    $state=@{ Views=$views; Elapsed=0; Posts=@(); PostedAt=@(); Waits=0; BadSamples=0; TransientAfterClose=0
        ObserveCalls=0; BeforeObserve=$null; AfterPost=$null; KeepWindows=$false }
    $native=@{
        NewCloseClock={ [pscustomobject]@{ Start=$state.Elapsed } }.GetNewClosure()
        Elapsed={ param($clock) $state.Elapsed-$clock.Start }.GetNewClosure()
        Observe={
            $state.ObserveCalls++
            if ($state.BeforeObserve) { & $state.BeforeObserve $state }
            $bad=$state.BadSamples -gt 0
            if ($bad) { $state.BadSamples-- }
            [pscustomobject]@{ Reliable=(-not $bad); Views=@($state.Views); Errors=@(
                if ($bad) { [pscustomobject]@{ Message='TopLevelExplorerAndComScopeMismatch'; HResult=123 } }) }
        }.GetNewClosure()
        ProbeWindow={ param($fp) if ($fp.RootHwnd -in @($state.Views.RootHwnd)) { 'StillPresent' } else { 'Gone' } }.GetNewClosure()
        CloseWindow={
            param($view)
            $state.Posts+=$view.RootHwnd; $state.PostedAt+=$state.Elapsed
            if (-not $state.KeepWindows) { $state.Views=@($state.Views | Where-Object RootHwnd -ne $view.RootHwnd) }
            $state.BadSamples=$state.TransientAfterClose
            if ($state.AfterPost) { & $state.AfterPost $state $view }
            'Posted'
        }.GetNewClosure()
        Wait={ $state.Elapsed+=200; $state.Waits++ }.GetNewClosure()
    }
    @{ State=$state; Native=$native; Expected=[pscustomobject]@{ Reliable=$true; Views=$views; Errors=@() }
        Prefix=(Join-Path $script:storage ([guid]::NewGuid().ToString('N'))) }
}
try {
    Test 'native request selects system-menu close of the root once without touching GUI' {
        $view=New-WizardExistingView; $view.RawHwnd=999
        $calls=[Collections.Generic.List[object]]::new()
        $probe={ param($fp) Assert ($fp.RootHwnd -eq 90); 'StillPresent' }
        $post={ param($handle,$message,$wparam,$lparam) $calls.Add(@($handle.ToInt64(),$message,$wparam.ToInt64(),$lparam.ToInt64())) }.GetNewClosure()
        $result=Invoke-SmokeWindowClose $view $probe $post
        Assert ($result -eq 'Posted' -and $calls.Count -eq 1 -and $calls[0][0] -eq 90)
        Assert ($calls[0][1] -eq 0x0112 -and $calls[0][2] -eq 0xF060 -and $calls[0][3] -eq 0) 'Use WM_SYSCOMMAND/SC_CLOSE for the whole window, not direct WM_CLOSE'
    }
    Test 'message boundary retains final fingerprint gates and forwards send errors without retries' {
        foreach ($kind in @('Gone','Changed','ProbeError','SendError')) {
            $state=@{ Kind=$kind; Probes=0; Posts=0 }
            $probe={ param($fp)
                $state.Probes++
                if ($state.Kind -eq 'ProbeError') { throw 'SyntheticProbeFailure' }
                if ($state.Kind -eq 'SendError') { return 'StillPresent' }
                $state.Kind
            }.GetNewClosure()
            $post={ param($handle,$message,$wparam,$lparam)
                $state.Posts++
                $exception=[ComponentModel.Win32Exception]::new(5,'SyntheticSendFailure'); $exception.Data['NativeErrorCode']=5; throw $exception
            }.GetNewClosure()
            $result=$null; $exception=$null
            try { $result=Invoke-SmokeWindowClose (New-WizardExistingView) $probe $post } catch { $exception=$_.Exception }
            Assert ($state.Probes -eq 1)
            if ($kind -eq 'Gone') { Assert ($result -eq 'Gone' -and $null -eq $exception -and $state.Posts -eq 0) }
            if ($kind -eq 'Changed') { Assert ($exception.Message -like 'CloseFingerprintChanged:*' -and $state.Posts -eq 0) }
            if ($kind -eq 'ProbeError') { Assert ($exception.Message -eq 'SyntheticProbeFailure' -and $state.Posts -eq 0) }
            if ($kind -eq 'SendError') { Assert ($exception.Data['NativeErrorCode'] -eq 5 -and $state.Posts -eq 1) }
        }
    }
    Test 'lifecycle uses actual request selection when a tab-close message would leave the root alive' {
        $f=New-CloseFixture; $state=$f.State
        $f.Expected.Views[0].Path='C:\synthetic\A'; $f.Expected.Views[1].Path='C:\synthetic\C'
        $b=$f.Expected.Views[0] | Select-Object *; $b.Identity='tab-B'; $b.Path='C:\synthetic\B'
        $f.Expected.Views+=@($b); $state.Views=$f.Expected.Views
        $send=${function:Invoke-SmokeWindowClose}; $probe=$f.Native.ProbeWindow
        $post={ param($handle,$message,$wparam,$lparam)
            $root=$handle.ToInt64(); $state.Posts+=$root
            if ($message -eq 0x0010) {
                # VM evidence: direct WM_CLOSE removes active B, keeping root 10/A alive.
                $active=@($state.Views | Where-Object RootHwnd -eq $root)[-1]
                $state.Views=@($state.Views | Where-Object Identity -ne $active.Identity)
            } elseif ($message -eq 0x0112 -and $wparam.ToInt64() -eq 0xF060) {
                $state.Views=@($state.Views | Where-Object RootHwnd -ne $root)
            } else { throw 'Unexpected window-close request' }
        }.GetNewClosure()
        $f.Native.CloseWindow={ param($view) & $send $view $probe $post }.GetNewClosure()
        Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix
        Assert (($state.Posts -join ',') -eq '10,20' -and $state.Views.Count -eq 0)
        $ledger=Get-Content -LiteralPath ($f.Prefix+'-actions.json') -Raw | ConvertFrom-Json
        Assert (@($ledger | Where-Object State -eq 'Closed').Count -eq 2)
    }
    Test 'a tab-only close never counts as window disappearance or triggers repeated closing' {
        $f=New-CloseFixture; $state=$f.State
        $b=$f.Expected.Views[0] | Select-Object *; $b.Identity='tab-B'; $b.Path='C:\synthetic\B'
        $f.Expected.Views+=@($b); $state.Views=$f.Expected.Views
        $f.Native.CloseWindow={ param($view) $state.Posts+=$view.RootHwnd; $state.Views=@($state.Views | Where-Object Identity -ne 'tab-B'); 'Posted' }.GetNewClosure()
        $exception=$null
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
        Assert ($exception.Message -like 'ExplorerCloseIncomplete:*' -and ($state.Posts -join ',') -eq '10')
        Assert ($state.Views.Count -eq 2 -and $state.Elapsed -eq 10000)
        $ledger=Get-Content -LiteralPath ($f.Prefix+'-actions.json') -Raw | ConvertFrom-Json
        Assert ($ledger[0].State -eq 'TimedOut' -and $ledger[1].State -eq 'Planned')
    }
    Test 'multi-root close waits through incomplete observations and posts each root once' {
        $f=New-CloseFixture; $f.State.TransientAfterClose=2
        Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix
        Assert (($f.State.Posts -join ',') -eq '10,20' -and $f.State.Views.Count -eq 0 -and $f.State.Waits -ge 4)
        Assert ($f.State.PostedAt[1] -ge 600) 'Second post must wait for recovery and two separated reliable samples'
        $trace=@(Get-Content -LiteralPath ($f.Prefix+'-observations.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
        $bad=@($trace | Where-Object { $_.Event -eq 'Observe' -and -not $_.Detail.Observation.Reliable })
        Assert ($bad.Count -eq 4 -and $bad[0].Detail.Observation.Errors[0].HResult -eq 123)
        $ledger=Get-Content -LiteralPath ($f.Prefix+'-actions.json') -Raw | ConvertFrom-Json
        Assert (@($ledger | Where-Object State -eq 'Closed').Count -eq 2 -and @($ledger | Where-Object Posted).Count -eq 2)
    }
    Test 'zero, single and many roots preserve duplicate paths and close all tabs by root once' {
        foreach ($roots in @(@(),@(10),@(10,20,30))) {
            $f=New-CloseFixture -Roots $roots
            $extra=@(foreach ($v in $f.State.Views) { $copy=$v | Select-Object *; $copy.Identity+='-tab2'; $copy })
            $f.State.Views=@($f.State.Views)+$extra; $f.Expected.Views=$f.State.Views
            Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix
            Assert ($f.State.Posts.Count -eq $roots.Count -and @($f.State.Posts | Select-Object -Unique).Count -eq $roots.Count)
            Assert ($f.State.Views.Count -eq 0 -and $f.State.Waits -ge 1)
        }
    }
    Test 'initial incomplete scope never starts posting or retries observation' {
        $f=New-CloseFixture; $f.State.BadSamples=1; $caught=$false
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $caught=$_.Exception.Message -like 'ExplorerObservationIncomplete:*' }
        Assert ($caught -and $f.State.Posts.Count -eq 0 -and $f.State.Waits -eq 0)
    }
    Test 'permanent incomplete observation expires once and leaves all later roots unsent' {
        $f=New-CloseFixture; $f.State.TransientAfterClose=1000; $exception=$null
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
        Assert ($exception.Message -like 'CloseObservationTimedOut:*' -and ($f.State.Posts -join ',') -eq '10')
        Assert ($f.State.Elapsed -eq 10000 -and $f.State.Waits -eq 50)
        Assert ($exception.Data['CloseSummary'] -like '*尚未嘗試投遞 1 個*')
        $ledger=Get-Content -LiteralPath ($f.Prefix+'-actions.json') -Raw | ConvertFrom-Json
        Assert ($ledger[0].State -eq 'TimedOut' -and $ledger[1].State -eq 'Planned')
    }
    Test 'live original target expires without a second close request' {
        $f=New-CloseFixture; $f.State.KeepWindows=$true; $exception=$null
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
        Assert ($exception.Message -like 'ExplorerCloseIncomplete:*' -and ($f.State.Posts -join ',') -eq '10' -and $f.State.Elapsed -eq 10000)
    }
    Test 'the deadline includes first observation time and is not reset per root' {
        $f=New-CloseFixture
        $f.State.BeforeObserve={ param($s) $s.Elapsed+=1000 }
        $f.State.AfterPost={ param($s,$v) if ($v.RootHwnd -eq 20) { $s.BadSamples=1000 } }
        $exception=$null
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
        Assert ($exception.Message -like 'CloseObservationTimedOut:*' -and $f.State.Elapsed -ge 10000 -and $f.State.Elapsed -lt 11200)
        Assert (($f.State.Posts -join ',') -eq '10,20')
    }
    Test 'temporary original presence and thrown observation recover before the next post' {
        $f=New-CloseFixture; $f.State.KeepWindows=$true
        $f.State.BeforeObserve={ param($s)
            if ($s.Posts.Count -eq 1 -and $s.Elapsed -lt 400) { throw 'SyntheticComWindowGone' }
            if ($s.Posts.Count -gt 0 -and $s.Elapsed -ge 400) { $s.Views=@($s.Views | Where-Object RootHwnd -notin $s.Posts) }
        }
        Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix
        Assert (($f.State.Posts -join ',') -eq '10,20' -and $f.State.PostedAt[1] -ge 600)
        $trace=Get-Content -LiteralPath ($f.Prefix+'-observations.jsonl') -Raw
        Assert ($trace.Contains('SyntheticComWindowGone') -and $trace.Contains('"Stage":"Observe"'))
    }
    Test 'COM-first and Win32-first disappearance must agree before declaring a target gone' {
        foreach ($stale in @('Com','Win32')) {
            $f=New-CloseFixture; $state=$f.State
            $f.State.BeforeObserve={ param($s)
                if ($stale -eq 'Com' -and $s.Posts.Count -gt 0 -and $s.Elapsed -lt 400) { $s.Views=@($f.Expected.Views) }
                else { $s.Views=@($s.Views | Where-Object RootHwnd -notin $s.Posts) }
            }.GetNewClosure()
            $f.Native.ProbeWindow={ param($fp)
                if ($fp.RootHwnd -notin $state.Posts -or ($stale -eq 'Win32' -and $state.Elapsed -lt 400)) { 'StillPresent' } else { 'Gone' }
            }.GetNewClosure()
            Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix
            Assert ($f.State.PostedAt[1] -ge 600 -and ($f.State.Posts -join ',') -eq '10,20')
        }
    }
    Test 'one empty sample followed by an unknown window cannot be reported as success' {
        $f=New-CloseFixture -Roots @(10)
        $f.State.BeforeObserve={ param($s)
            if ($s.Posts.Count -eq 1 -and $s.Elapsed -ge 200) { $s.Views=@(New-WizardExistingView) }
        }
        $caught=$false
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $caught=$_.Exception.Message -like 'CloseScopeChanged:*' }
        Assert ($caught -and ($f.State.Posts -join ',') -eq '10' -and $f.State.Views[0].RootHwnd -eq 90)
    }
    Test 'incomplete samples with a known foreign Win32 root stop without waiting or sending more' {
        $f=New-CloseFixture; $state=$f.State
        $f.Native.Observe={ [pscustomobject]@{ Reliable=($state.Posts.Count -eq 0); Views=@($state.Views); Errors=@()
            Win32Roots=$(if ($state.Posts.Count) { @(20,99) } else { @(10,20) }) } }.GetNewClosure()
        $caught=$false
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $caught=$_.Exception.Message -like 'CloseScopeChanged:*' }
        Assert ($caught -and ($state.Posts -join ',') -eq '10' -and $state.Waits -eq 0)
    }
    Test 'a missing tab in an unsent window remains a terminal original-fixture change' {
        $f=New-CloseFixture
        $copy=$f.Expected.Views[1] | Select-Object *; $copy.Identity='second-tab'
        $f.Expected.Views+=@($copy); $f.State.Views=$f.Expected.Views
        $f.State.AfterPost={ param($s,$v) $s.Views=@($s.Views | Where-Object Identity -ne 'second-tab') }
        $caught=$false
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $caught=$_.Exception.Message -eq 'OriginalFixtureChanged' }
        Assert ($caught -and ($f.State.Posts -join ',') -eq '10')
    }
    Test 'unknown probes are never interpreted as Gone and a reused HWND stops immediately' {
        foreach ($status in @('Unknown','Changed')) {
            $f=New-CloseFixture; $state=$f.State
            $f.Native.ProbeWindow={ param($fp)
                if ($state.Posts.Count) { if ($status -eq 'Unknown') { throw 'SyntheticAccessDenied' }; return 'Changed' }
                'StillPresent'
            }.GetNewClosure()
            $exception=$null
            try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
            Assert (($state.Posts -join ',') -eq '10')
            if ($status -eq 'Unknown') { Assert ($exception.Message -like 'CloseObservationTimedOut:*' -and $state.Elapsed -eq 10000) }
            else { Assert ($exception.Message -like 'CloseFingerprintChanged:*' -and $state.Waits -eq 0) }
        }
    }
    Test 'already-gone windows including disappearance at the final native gate are never posted' {
        foreach ($finalGate in @($false,$true)) {
            $f=New-CloseFixture -Roots @(10)
            if ($finalGate) {
                $state=$f.State
                $f.Native.CloseWindow={ param($view) $state.Views=@(); 'Gone' }.GetNewClosure()
            } else { $f.State.Views=@() }
            Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix
            Assert ($f.State.Posts.Count -eq 0)
            $ledger=Get-Content -LiteralPath ($f.Prefix+'-actions.json') -Raw | ConvertFrom-Json
            Assert ($ledger[0].State -eq 'AlreadyGone' -and -not $ledger[0].Posted)
        }
        $f=New-CloseFixture -Roots @(10); $f.State.Views=@()
        $f.State.BeforeObserve={ param($s) if ($s.Elapsed -ge 200) { $s.Views=@(New-WizardExistingView) } }
        $exception=$null
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
        Assert ($exception.Message -like 'CloseScopeChanged:*' -and $f.State.Posts.Count -eq 0)
        Assert ($exception.Data['CloseSummary'] -like '*已確認消失 0 個*') 'One native Gone sample must not become a terminal AlreadyGone claim'
    }
    Test 'posting failure preserves native error and never retries any window' {
        $f=New-CloseFixture; $state=$f.State
        $f.Native.CloseWindow={ param($view)
            $state.Posts+=$view.RootHwnd
            $closeException=[InvalidOperationException]::new('SyntheticPostFailure'); $closeException.Data['NativeErrorCode']=5; throw $closeException
        }.GetNewClosure()
        $exception=$null
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
        Assert ($exception.Message -eq 'SyntheticPostFailure' -and $exception.Data['NativeErrorCode'] -eq 5 -and ($state.Posts -join ',') -eq '10')
        $ledger=Get-Content -LiteralPath ($f.Prefix+'-actions.json') -Raw | ConvertFrom-Json
        Assert ($ledger[0].State -eq 'Failed' -and $ledger[1].State -eq 'Planned')
    }
    Test 'Posting and Posted persistence failures stop without resending and retain uncertainty' {
        foreach ($failState in @('Posting','Posted')) {
            $f=New-CloseFixture
            $write=${function:Write-SmokeJson}
            & {
                function Write-SmokeJson {
                    param($Path,$Value,[switch]$New)
                    if ($Path.EndsWith('-actions.json') -and @($Value | Where-Object State -eq $failState).Count) { throw "SyntheticWrite-$failState" }
                    & $write $Path $Value -New:$New
                }
                $exception=$null
                try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
                Assert ($exception.Message -eq "SyntheticWrite-$failState")
                $expectedCount=0; if ($failState -eq 'Posted') { $expectedCount=1 }
                Assert ($f.State.Posts.Count -eq $expectedCount)
            }
        }
    }
    Test 'close evidence rejects replay and never serializes COM references' {
        $f=New-CloseFixture
        $f.Expected.Views[0] | Add-Member ComObject 'synthetic-secret-RCW'
        Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix
        $count=$f.State.Posts.Count; $caught=$false
        try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $caught=$true }
        Assert ($caught -and $f.State.Posts.Count -eq $count)
        $text=(@(Get-ChildItem -LiteralPath $script:storage -Filter ([IO.Path]::GetFileName($f.Prefix)+'*') |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join '')
        Assert (-not $text.Contains('synthetic-secret-RCW') -and -not $text.Contains('ComObject'))
    }
    Test 'recovery just before the common deadline succeeds only with two stable samples' {
        foreach ($badSamples in @(47,48)) {
            $f=New-CloseFixture; $f.State.TransientAfterClose=$badSamples
            $f.State.AfterPost={ param($s,$v) if ($v.RootHwnd -eq 20) { $s.BadSamples=0 } }
            $exception=$null
            try { Close-SmokeWindows $f.Expected $f.Native 10 $f.Prefix } catch { $exception=$_.Exception }
            Assert (($f.State.Posts -join ',') -eq '10,20')
            if ($badSamples -eq 47) { Assert ($null -eq $exception -and $f.State.Elapsed -eq 9800) }
            else { Assert ($exception.Message -like 'CloseObservationTimedOut:*' -and $f.State.Elapsed -eq 10000) }
        }
    }
    Test 'observation history is bounded and each retained row is independently readable JSON' {
        $f=New-CloseFixture
        $context=@{ Native=$f.Native; Clock=(& $f.Native.NewCloseClock); Prefix=$f.Prefix; TraceCount=0 }
        foreach ($n in 1..300) { Write-SmokeCloseTrace $context 'Synthetic' @{ Number=$n } }
        $rows=@(Get-Content -LiteralPath ($f.Prefix+'-observations.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
        Assert ($rows.Count -eq 256 -and $context.TraceCount -eq 256 -and $rows[255].Sequence -eq 255)
    }
    Test 'startup E01 and E02 cleanup all recover from closing transitions before advancing' {
        foreach ($stage in @('Existing','E01','E02')) {
            $f=New-WizardFixture; $f.State.Views=@(New-WizardExistingView); $f.State.TransientCase=$stage
            $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
            Assert ($r.Status -eq 'Passed' -and $f.State.Closes.Count -eq 6 -and $f.State.Views.Count -eq 0) $r.Reason
            $saved=Get-Content -LiteralPath (Join-Path $r.SuiteRoot 'suite-result.json') -Raw | ConvertFrom-Json
            Assert ($saved.Phase -eq 'Complete' -and $saved.Status -eq 'Passed')
        }
    }
    Test 'startup E01 and E02 cleanup timeouts stop all later actions and preserve case results' {
        foreach ($stage in @('Existing','E01','E02')) {
            $f=New-WizardFixture; $f.State.Views=@(New-WizardExistingView); $f.State.PermanentCase=$stage
            $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
            Assert ($r.Status -eq 'Failed' -and $r.Reason -like 'CloseObservationTimedOut:*' -and $r.Error.CloseSummary)
            if ($stage -eq 'Existing') { Assert (-not $r.E01Root -and $f.State.Closes.Count -eq 1) }
            if ($stage -eq 'E01') { Assert ($r.E01 -eq 'Passed' -and -not $r.E02Root -and 'Prepare:E02' -notin $f.State.Calls) }
            if ($stage -eq 'E02') { Assert ($r.E02 -eq 'Passed' -and $r.Phase -eq 'E02-AutomaticClose') }
            $saved=Get-Content -LiteralPath (Join-Path $r.SuiteRoot 'suite-result.json') -Raw | ConvertFrom-Json
            Assert ($saved.Status -eq 'Failed' -and @($saved.Steps | Where-Object Phase -eq 'Complete').Count -eq 0)
        }
    }
    Test 'default wizard does not prompt, read runtime, create files or call CLI' {
        $f=New-WizardFixture; $r=Invoke-SmokeOneClick $false $f.Adapter
        Assert ($r.Status -eq 'NotRun' -and $f.State.Calls.Count -eq 0 -and $f.State.FactsReads -eq 0 -and -not $r.SuiteRoot)
    }
    Test 'declined isolation consent has no runtime or GUI operations' {
        $f=New-WizardFixture; $f.State.Consent=$false; $r=Invoke-SmokeOneClick $true $f.Adapter
        Assert ($r.Status -eq 'NotRun' -and $f.State.FactsReads -eq 0 -and $f.State.CliCalls -eq 0)
    }
    Test 'invalid actual runtime blocks before baseline or fixture creation' {
        $f=New-WizardFixture; $f.Facts.Apartment='MTA'; $r=Invoke-SmokeOneClick $true $f.Adapter
        Assert ($r.Status -eq 'Blocked' -and -not $r.SuiteRoot -and $f.State.CliCalls -eq 0)
    }
    Test 'baseline failure prevents all GUI and harness calls' {
        $f=New-WizardFixture; $f.State.BaselineFailed=$true; $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Blocked' -and $f.State.CliCalls -eq 0 -and 'Preflight:E01' -notin $f.State.Calls)
    }
    Test 'unidentifiable existing window scope stops before any close or setup Restore' {
        $f=New-WizardFixture
        $f.State.Views=@([pscustomobject]@{ Identity='foreign'; RawHwnd=99; RootHwnd=99; Path='C:\foreign'; Visible=$true; Fingerprint=@{ SessionId=10 } })
        $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Blocked' -and $f.State.CliCalls -eq 0 -and $f.State.Closes.Count -eq 0)
    }
    Test 'setup uses exactly one real-CLI-shaped request and a nonzero exit cannot replay' {
        $f=New-WizardFixture; $f.State.SetupExit=42; $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Failed' -and $f.State.CliCalls -eq 1 -and 'Run:E01' -notin $f.State.Calls)
        $saved=Get-Content -LiteralPath (Join-Path $r.E01Root 'smoke-result.json') -Raw | ConvertFrom-Json
        Assert ($saved.Status -eq 'Failed')
        $prepared=[pscustomobject]@{ TestRoot=$r.E01Root; Facts=$f.Facts }
        $rejected=$false
        try { Initialize-SmokeOneClickE01 $prepared $f.Adapter.Native { } } catch { $rejected=$true }
        Assert ($rejected -and $f.State.CliCalls -eq 1)
    }
    Test 'unverified setup report prevents E01 Capture and preserves setup evidence' {
        $f=New-WizardFixture; $f.State.SetupUnverified=$true; $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Failed' -and $f.State.CliCalls -eq 1 -and 'Run:E01' -notin $f.State.Calls)
        Assert (Test-Path -LiteralPath (Join-Path $r.E01Root 'E01\setup-report.json'))
    }
    Test 'missing visual review leaves pending results and prevents E02' {
        $f=New-WizardFixture; $f.State.Review=$false; $r=Invoke-SmokeOneClick $true $f.Adapter $true; Remember-WizardSuite $r
        Assert ($r.Status -eq 'AwaitingVisualReview' -and $r.E01 -eq 'AwaitingVisualReview' -and $r.E02 -eq 'NotRun')
        Assert ('Confirm:E01' -notin $f.State.Calls -and 'Prepare:E02' -notin $f.State.Calls)
    }
    Test 'automatic close failure preserves E01 Passed and prevents E02' {
        $f=New-WizardFixture; $f.State.Cleanup=$false; $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Failed' -and $r.E01 -eq 'Passed' -and $r.E02 -eq 'NotRun' -and 'Prepare:E02' -notin $f.State.Calls)
    }
    Test 'automatic close must independently confirm empty scope before E02' {
        $f=New-WizardFixture; $f.State.KeepWindows=$true; $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Failed' -and $r.E01 -eq 'Passed' -and 'Prepare:E02' -notin $f.State.Calls)
    }
    Test 'case failure stops before manual review and the second case' {
        $f=New-WizardFixture; $f.State.RunFailed=$true; $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Failed' -and $r.E01 -eq 'Failed' -and 'Visual:E01' -notin $f.State.Calls -and 'Prepare:E02' -notin $f.State.Calls)
    }
    Test 'synthetic default runs without visual prompts, uses distinct roots and persists every phase' {
        $f=New-WizardFixture; $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Passed' -and $r.E01 -eq 'Passed' -and $r.E02 -eq 'Passed') $r.Reason
        Assert ($r.E01Root -ne $r.E02Root -and $f.State.CliCalls -eq 1)
        Assert (@($f.State.Calls | Where-Object { $_ -like 'Visual:*' -or $_ -like 'Cleanup:*' }).Count -eq 0)
        Assert ($r.VisualReview -eq 'NotRun' -and $f.State.Closes.Count -eq 5 -and $f.State.Views.Count -eq 0)
        Assert ($f.State.Calls.IndexOf('CloseWindow') -lt $f.State.Calls.IndexOf('Prepare:E02'))
        $saved=Get-Content -LiteralPath (Join-Path $r.SuiteRoot 'suite-result.json') -Raw | ConvertFrom-Json
        Assert ($saved.Status -eq 'Passed' -and @($saved.Steps | Where-Object Phase -eq 'E01-SetupRestore').Count -eq 1)
        Assert (Test-Path -LiteralPath (Join-Path $r.E01Root 'E01\setup-observation.json'))
    }
    Test 'optional visual mode still requires two genuine operator responses' {
        $f=New-WizardFixture; $r=Invoke-SmokeOneClick $true $f.Adapter $true; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Passed' -and $r.VisualReview -eq 'Passed') $r.Reason
        Assert ((@($f.State.Calls | Where-Object { $_ -like 'Visual:*' }) -join ',') -eq 'Visual:E01,Visual:E02')
        Assert ('Confirm:E01' -in $f.State.Calls -and 'Confirm:E02' -in $f.State.Calls)
    }
    Test 'real prompts accept optional empty notes but never treat empty PASS as visual approval' {
        $answers=[Collections.Generic.Queue[string]]::new()
        foreach ($answer in @('VM','','PASS','','')) { $answers.Enqueue($answer) }
        function Read-Host { param($Prompt) $answers.Dequeue() }
        $prompt=(New-SmokeOneClickAdapter).Prompt
        $consent=& $prompt 'Isolation' '' ''
        Assert ($consent.Kind -eq 'DisposableVM' -and -not [string]::IsNullOrWhiteSpace($consent.Notes))
        $review=& $prompt 'Visual' 'E01' 'synthetic-root'
        Assert ($review.Approved -and $review.Notes -like 'Operator visually confirmed:*')
        Assert ($null -eq (& $prompt 'Visual' 'E02' 'synthetic-root'))
        Assert ($answers.Count -eq 0)
    }
    Test 'cancelling existing-window choice preserves windows and prevents Capture and setup' {
        $f=New-WizardFixture; $f.State.Views=@(New-WizardExistingView); $f.State.ExistingChoice=$null
        $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'NotRun' -and $f.State.Closes.Count -eq 0 -and $f.State.CliCalls -eq 0 -and -not $r.E01Root)
    }
    Test 'existing Explorer windows can be closed without snapshot and no longer block testing' {
        $f=New-WizardFixture; $f.State.Views=@(New-WizardExistingView)
        $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Passed' -and $f.State.Closes[0] -eq 90 -and $f.State.Closes.Count -eq 6) $r.Reason
        Assert ('ExistingCapture' -notin $f.State.Calls -and -not $r.ExistingSnapshot)
    }
    Test 'existing Capture is verified and recorded before the first window close' {
        $f=New-WizardFixture; $f.State.Views=@(New-WizardExistingView); $f.State.ExistingChoice='Save'
        $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Passed' -and (Test-Path -LiteralPath $r.ExistingSnapshot)) $r.Reason
        Assert ($f.State.Calls.IndexOf('ExistingCapture') -lt $f.State.Calls.IndexOf('CloseWindow'))
        Assert (Test-Path -LiteralPath (Join-Path $r.SuiteRoot 'existing-snapshot-validation.json'))
    }
    Test 'failed or incomplete Capture closes no existing windows and never starts E01' {
        foreach ($failure in @('Exit','Mismatch')) {
            $f=New-WizardFixture; $f.State.Views=@(New-WizardExistingView); $f.State.ExistingChoice='Save'
            if ($failure -eq 'Exit') { $f.State.CaptureExit=42 } else { $f.State.CaptureMismatch=$true }
            $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
            Assert ($r.Status -eq 'Blocked' -and $f.State.Closes.Count -eq 0 -and -not $r.E01Root)
        }
    }
    Test 'incomplete observation reports a useful reason and never offers or attempts closure' {
        $f=New-WizardFixture; $f.State.Reliable=$false
        $r=Invoke-SmokeOneClick $true $f.Adapter; Remember-WizardSuite $r
        Assert ($r.Status -eq 'Blocked' -and $r.Reason -like 'ExplorerObservationIncomplete:*' -and $f.State.Closes.Count -eq 0)
        Assert ('ExistingWindows:' -notin $f.State.Calls)
        Assert (Test-Path -LiteralPath (Join-Path $r.SuiteRoot 'existing-observation.json'))
    }
    Test 'changed tab, reused handle or foreign session prevents close at final observation' {
        foreach ($property in @('Path','Identity','PID','SessionId','ProcessStartedAtUtc')) {
            $f=New-WizardFixture; $old=New-WizardExistingView
            $view=New-WizardExistingView
            switch ($property) {
                Path { $view.Path='C:\changed' }; Identity { $view.Identity='replacement' }
                PID { $view.Fingerprint.PID=43 }; SessionId { $view.Fingerprint.SessionId=11 }
                ProcessStartedAtUtc { $view.Fingerprint.ProcessStartedAtUtc='2026-11-03T00:00:00Z' }
            }
            $f.State.Views=@($view)
            $prefix=Join-Path $script:storage ('changed-'+$property)
            $caught=$false
            try { Close-SmokeWindows ([pscustomobject]@{ Reliable=$true; Views=@($old) }) $f.Adapter.Native 10 $prefix } catch { $caught=$true }
            Assert ($caught -and $f.State.Closes.Count -eq 0)
        }
    }
    Test 'a new unexpected window after first close is preserved and stops subsequent closes' {
        $f=New-WizardFixture; $v=New-WizardExistingView; $f.State.Views=@($v)
        $state=$f.State
        $f.Adapter.Native.CloseWindow={ param($view) $state.Closes+=$view.RootHwnd; $state.Views=@(New-WizardExistingView); $state.Views[0].Identity='new-window' }.GetNewClosure()
        $caught=$false
        try { Close-SmokeWindows ([pscustomobject]@{ Reliable=$true; Views=@($v) }) $f.Adapter.Native 10 (Join-Path $script:storage 'new-window') } catch { $caught=$true }
        Assert ($caught -and $state.Closes.Count -eq 1 -and $state.Views[0].Identity -eq 'new-window')
    }
    Test 'another launcher holding the same coordinator lock blocks before GUI' {
        $handle=[IO.File]::Open((Get-SmokeOneClickLockPath),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            $f=New-WizardFixture; $r=Invoke-SmokeOneClick $true $f.Adapter
            Assert ($r.Status -eq 'Blocked' -and $f.State.CliCalls -eq 0 -and -not $r.SuiteRoot)
        } finally { $handle.Dispose() }
    }
    Test 'public default and import remain safe; cmd uses STA without policy bypass' {
        $entry=Join-Path $PSScriptRoot 'Integration\Start-ExplorerSmoke.ps1'; $engine=(Get-Process -Id $PID).Path
        $json=& $engine -NoProfile -Sta -File $entry; $code=$LASTEXITCODE
        $r=($json -join "`n") | ConvertFrom-Json
        Assert ($code -eq 2 -and $r.Status -eq 'NotRun' -and -not $r.SuiteRoot)
        $output=@(& $engine -NoProfile -Sta -Command ". '$($entry.Replace("'","''"))'; 'ImportedWithoutDispatch'")
        Assert ($LASTEXITCODE -eq 0 -and ($output -join '') -eq 'ImportedWithoutDispatch')
        $cmd=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Integration\Run-ExplorerSmoke.cmd') -Raw
        Assert ($cmd.Contains('-NoProfile -Sta -File "%~dp0Start-ExplorerSmoke.ps1" -Run') -and -not $cmd.Contains('-ExecutionPolicy'))
    }
} finally {
    foreach ($root in @($script:owned | Select-Object -Unique)) {
        $full=[IO.Path]::GetFullPath($root)
        Assert ([IO.Path]::GetDirectoryName($full).TrimEnd('\') -ieq [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\'))
        Assert ([IO.Path]::GetFileName($full) -match '^ResumeExplorer-E2E-(Suite-)?[a-f0-9]{32}$')
        Remove-Item -LiteralPath $full -Recurse -Force
    }
    $full=[IO.Path]::GetFullPath($script:storage)
    Assert ([IO.Path]::GetDirectoryName($full).TrimEnd('\') -ieq [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\'))
    Assert ([IO.Path]::GetFileName($full) -like 'SmokeWizardTests-*')
    Remove-Item -LiteralPath $full -Recurse -Force
}
Write-Host "$script:passed one-click harness tests passed. All GUI routes synthetic; live E01/E02 NotRun."
