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
        ExistingChoice='Close'; CaptureExit=0; CaptureMismatch=$false; Closes=@(); Reliable=$true }
    $facts=[pscustomobject]@{ Windows=$true; Build=22631; Edition='Core'; Major=7; Version='Synthetic'; Apartment='STA'
        Interactive=$true; SessionId=10; ComputerName='SYNTHETIC-VM'; UserSid='SYNTHETIC-SID'
        DesktopAccessible=$true; DesktopName='Default'; CurrentDesktopName='Default' }
    $write=${function:Write-SmokeJson}; $invokeHarness=${function:Invoke-ExplorerSmoke}; $owned=$script:owned
    $native=@{
        Facts={ $state.FactsReads++; $facts }.GetNewClosure()
        Observe={ [pscustomobject]@{ Reliable=$state.Reliable; Views=@($state.Views); Errors=@(); ObservedAtUtc='synthetic'; ForegroundHwnd=0 } }.GetNewClosure()
        Uia={ param($views) $state.Calls+='Uia' }.GetNewClosure()
        CloseWindow={
            param($view)
            if (-not $state.Cleanup) { throw 'SyntheticCloseRejected' }
            $state.Closes+=$view.RootHwnd; $state.Calls+='CloseWindow'
            if (-not $state.KeepWindows) { $state.Views=@($state.Views | Where-Object RootHwnd -ne $view.RootHwnd) }
        }.GetNewClosure()
        Wait={ throw 'SyntheticCloseStillPending' }
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
try {
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
