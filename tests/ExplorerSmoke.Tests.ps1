# Offline tests of harness safety/assertions, never evidence of real E01/E02 success.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Integration\ExplorerSmoke.Core.ps1')
$script:passed=0
function Assert($Condition,$Message='Assertion failed') { if (-not $Condition) { throw $Message } }
function Test($Name,[scriptblock]$Body) { & $Body; $script:passed++; Write-Host "PASS $Name" }
function Reject([scriptblock]$Body) { $caught=$false; try { & $Body } catch { $caught=$true }; Assert $caught 'Expected fail-closed rejection' }
function New-TestFacts {
    [pscustomobject]@{ Windows=$true; Build=22631; Edition='Core'; Major=7; Version='synthetic'
        Apartment='STA'; Interactive=$true; SessionId=10; ComputerName='SMOKE-VM'; UserSid='S-1-5-21-SYNTHETIC'
        DesktopAccessible=$true; DesktopName='Default'; CurrentDesktopName='Default' }
}
function New-TestEvidence {
    [pscustomobject]@{ Kind='DisposableVM'; Dedicated=$true; ComputerName='SMOKE-VM'; UserSid='S-1-5-21-SYNTHETIC'
        SessionId=10; DesktopName='Default'; Notes='Synthetic offline fixture, not a real environment attestation.' }
}
function New-TestOptions([string]$Mode='Preflight',[string]$Case='E01') {
    @{ Mode=$Mode; Case=$Case; ConfirmIsolatedSession=$false; SessionEvidence=''; AllowExplorerUiChanges=$false
        TestRoot=''; ConfirmVisibleAndGrouping=$false; VisualEvidence='' }
}
function New-TestView([string]$Id,[long]$Root,[string]$Path) {
    [pscustomobject]@{ Identity=$Id; RawHwnd=$Root; RootHwnd=$Root; Path=$Path; Visible=$true
        Fingerprint=[pscustomobject]@{ Hwnd=$Root; RootHwnd=$Root; PID=42; SessionId=10; ProcessStartedAtUtc='2026-11-02T00:00:00Z' } }
}
function New-TestObservation($Views) { [pscustomobject]@{ Reliable=$true; Views=@($Views); ObservedAtUtc='synthetic'; ForegroundHwnd=0; Errors=@() } }
function New-FakeAdapter($State) {
    @{
        Facts={ $State.FactReads++; New-TestFacts }.GetNewClosure()
        Observe={ $State.Observes++; New-TestObservation @() }.GetNewClosure()
        Uia={ param($views) $State.Uia++ }.GetNewClosure()
        Cli={ param($arguments,$prefix) $State.Cli++; throw 'Offline tests must not launch a CLI' }.GetNewClosure()
    }
}
Test 'default options do not query COM, UIA, session or CLI' {
    $state=@{ FactReads=0; Observes=0; Uia=0; Cli=0 }; $result=Invoke-ExplorerSmoke (New-TestOptions) (New-FakeAdapter $state)
    Assert ($result.Status -eq 'NotRun' -and $result.E01 -eq 'NotRun' -and $result.E02 -eq 'NotRun')
    Assert (($state.Values | Measure-Object -Sum).Sum -eq 0)
}
Test 'Run without GUI consent cannot query session or launch CLI' {
    $state=@{ FactReads=0; Observes=0; Uia=0; Cli=0 }; $options=New-TestOptions Run
    $options.ConfirmIsolatedSession=$true; $options.SessionEvidence='not-read.json'
    $result=Invoke-ExplorerSmoke $options (New-FakeAdapter $state)
    Assert ($result.Status -eq 'NotRun' -and ($state.Values | Measure-Object -Sum).Sum -eq 0)
}
Test 'session flag alone cannot establish isolation' {
    $facts=New-TestFacts
    foreach ($property in @('ComputerName','UserSid','SessionId','Kind','Dedicated','DesktopName','Notes')) {
        $evidence=New-TestEvidence
        switch ($property) { 'SessionId' { $evidence.SessionId=99 }; 'Dedicated' { $evidence.Dedicated=$false }; 'Notes' { $evidence.Notes='' }; default { $evidence.$property='wrong' } }
        Reject { Assert-SmokeSession $facts $evidence }
    }
}
Test 'unsupported host, MTA, noninteractive desktop and Session 0 are blocked' {
    foreach ($property in @('Windows','Build','Major','Edition','Apartment','Interactive','SessionId','DesktopAccessible','DesktopName','CurrentDesktopName')) {
        $facts=New-TestFacts
        switch ($property) {
            'Windows' { $facts.Windows=$false }; 'Build' { $facts.Build=19045 }; 'Major' { $facts.Major=5 }
            'Interactive' { $facts.Interactive=$false }; 'SessionId' { $facts.SessionId=0 }; 'DesktopAccessible' { $facts.DesktopAccessible=$false }
            default { $facts.$property='unsupported' }
        }
        Reject { Assert-SmokeSession $facts (New-TestEvidence) }
    }
}
Test 'scope requires exact full-window multisets; extra paths and unknown roots are rejected' {
    $a=New-TestView A 10 'C:\Synthetic\A'; $b=New-TestView B 10 'C:\Synthetic\B'; $c=New-TestView C 20 'C:\Synthetic\C'
    $groups=@(@{ Paths=@($a.Path,$b.Path) },@{ Paths=@($c.Path) })
    Assert-SmokeScope (New-TestObservation @($a,$b,$c)) $groups 10
    $foreign=New-TestView X 30 'C:\Foreign'
    Reject { Assert-SmokeScope (New-TestObservation @($a,$b,$c,$foreign)) $groups 10 }
    Reject { Assert-SmokeScope (New-TestObservation @($a,$b)) $groups 10 }
    $a.Visible=$false; Reject { Assert-SmokeScope (New-TestObservation @($a,$b,$c)) $groups 10 }
}
Test 'unreliable observations, wrong sessions and duplicate identities never pass scope' {
    $a=New-TestView A 10 'C:\Synthetic\A'; $group=@(@{ Paths=@($a.Path) }); $obs=New-TestObservation @($a)
    $obs.Reliable=$false; Reject { Assert-SmokeScope $obs $group 10 }; $obs.Reliable=$true
    Reject { Assert-SmokeScope $obs $group 11 }
    $obs.Views=@($a,$a); Reject { Assert-SmokeScope $obs @(@{ Paths=@($a.Path,$a.Path) }) 10 }
}
Test 'original tab identity/path/window/process replacement is rejected' {
    $a=New-TestView A 10 'C:\Synthetic\A'; $before=New-TestObservation @($a)
    foreach ($property in @('Identity','Path','RawHwnd','RootHwnd','Fingerprint')) {
        $changed=New-TestView A 10 'C:\Synthetic\A'
        if ($property -eq 'Fingerprint') { $changed.Fingerprint.PID=99 }
        elseif ($property -in @('RawHwnd','RootHwnd')) { $changed.$property=99 }
        else { $changed.$property='changed' }
        Reject { Assert-SmokeOriginalUnchanged $before (New-TestObservation @($changed)) }
    }
}
Test 'snapshot comparison retains duplicates and window grouping' {
    $snapshot=[pscustomobject]@{ Version=1; Windows=@(@{ Paths=@('A','A') },@{ Paths=@('C') }) }
    Assert-SmokeSnapshot $snapshot @(@{ Paths=@('C') },@{ Paths=@('A','A') })
    Reject { Assert-SmokeSnapshot $snapshot @(@{ Paths=@('A') },@{ Paths=@('C') }) }
    Reject { Assert-SmokeSnapshot $snapshot @(@{ Paths=@('A','C') },@{ Paths=@('A') }) }
}
Test 'report validation checks original indices, statuses and paths rather than report counts alone' {
    $snapshot=[pscustomobject]@{ Version=1; Windows=@(@{ Paths=@('A','B') }) }
    $report=[pscustomobject]@{ SchemaVersion=1; State='Completed'; Items=@(
        [pscustomobject]@{ GroupIndex=1; ItemIndex=1; RequestedPath='A'; Status='Verified' },
        [pscustomobject]@{ GroupIndex=1; ItemIndex=2; RequestedPath='B'; Status='SkippedInvalidPath' }) }
    Assert-SmokeReport $report $snapshot @('Verified','SkippedInvalidPath')
    foreach ($status in @('OutcomeUnknown','NotAttempted','Verified')) {
        $report.Items[1].Status=$status; Reject { Assert-SmokeReport $report $snapshot @('Verified','SkippedInvalidPath') }
    }
    $report.Items[1].Status='SkippedInvalidPath'; $report.Items[1].ItemIndex=99
    Reject { Assert-SmokeReport $report $snapshot @('Verified','SkippedInvalidPath') }
}
Test 'serialized observer evidence excludes live COM references' {
    $view=New-TestView A 10 'C:\Synthetic\A'; $view | Add-Member NoteProperty ComObject ([pscustomobject]@{ Secret='must not serialize RCW' })
    $json=ConvertTo-Json -InputObject (ConvertTo-SmokeEvidence (New-TestObservation @($view))) -Depth 12
    Assert (-not $json.Contains('ComObject') -and -not $json.Contains('Secret'))
}

$ownedRoots=New-Object System.Collections.ArrayList
$evidencePath=Join-Path $env:TEMP ('smoke-session-'+[guid]::NewGuid().ToString('N')+'.json')
Write-SmokeJson $evidencePath (New-TestEvidence) -New
try {
    # Avoid closures calling test-local functions from a dynamic module; capture ready-made objects.
    $facts=New-TestFacts; $empty=New-TestObservation @()
    $state=@{ Observes=0; Cli=0; Uia=0 }
    $adapter=@{ Facts={ $facts }.GetNewClosure(); Observe={ $state.Observes++; $empty }.GetNewClosure()
        Uia={ param($views) $state.Uia++ }.GetNewClosure(); Cli={ param($args,$prefix) $state.Cli++; throw 'No native CLI in offline tests' }.GetNewClosure() }
    Test 'read-only Preflight produces Ready with both E2E cases still NotRun' {
        $options=New-TestOptions; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath
        $result=Invoke-ExplorerSmoke $options $adapter
        Assert ($result.Status -eq 'Ready' -and $result.E01 -eq 'NotRun' -and $result.E02 -eq 'NotRun' -and $state.Cli -eq 0)
    }
    Test 'Prepare creates unique owned artifacts, leaves E02 B missing and never calls a CLI' {
        $options=New-TestOptions Prepare E02; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath
        $result=Invoke-ExplorerSmoke $options $adapter
        if ($result.TestRoot) { [void]$ownedRoots.Add($result.TestRoot) }
        Assert ($result.Status -eq 'Prepared') $result.Reason
        Assert ([IO.Directory]::Exists((Join-Path $result.TestRoot 'E02\A')) -and -not (Test-Path -LiteralPath (Join-Path $result.TestRoot 'E02\B')))
        $manifest=Assert-SmokeRoot $result.TestRoot $facts E02
        Assert ($manifest.Case -eq 'E02' -and $state.Cli -eq 0)
    }
    Test 'unsafe roots, changed ownership and repeated Run cannot overwrite prior evidence' {
        Reject { Assert-SmokeRoot 'C:\Production' $facts E02 }
        Reject { Assert-SmokeTempBase (Join-Path $env:LOCALAPPDATA 'ResumeExplorer\Runs') }
        Reject { Assert-SmokeTempBase (Join-Path $env:LOCALAPPDATA 'ResumeExplorer\Runs\temp') }
        $root=$ownedRoots[0]; $path=Join-Path $root 'smoke-result.json'
        $previous=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json; $previous.Status='Passed'; Write-SmokeJson $path $previous
        $before=(Get-FileHash -LiteralPath $path).Hash
        $options=New-TestOptions Run E02; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath
        $options.AllowExplorerUiChanges=$true; $options.TestRoot=$root
        $result=Invoke-ExplorerSmoke $options $adapter
        Assert ($result.Status -eq 'Blocked' -and $state.Cli -eq 0 -and (Get-FileHash -LiteralPath $path).Hash -eq $before)
        $wrong=$facts | Select-Object *; $wrong.UserSid='another-user'; Reject { Assert-SmokeRoot $root $wrong E02 }
    }
    Test 'foreign scope blocks Run before any public CLI or snapshot creation' {
        $root=$ownedRoots[0]; $path=Join-Path $root 'smoke-result.json'
        $previous=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json; $previous.Status='Prepared'; Write-SmokeJson $path $previous
        $foreign=New-TestObservation @((New-TestView X 99 'C:\Foreign'))
        $foreignAdapter=$adapter.Clone(); $foreignAdapter.Observe={ $foreign }.GetNewClosure()
        $options=New-TestOptions Run E02; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath
        $options.AllowExplorerUiChanges=$true; $options.TestRoot=$root
        $result=Invoke-ExplorerSmoke $options $foreignAdapter
        Assert ($result.Status -eq 'Blocked' -and $state.Cli -eq 0)
        Assert (-not (Test-Path -LiteralPath (Join-Path $root 'E02\retry-fixture.json')))
    }
    Test 'an active harness fixture lock prevents a second Run and preserves result evidence' {
        $root=$ownedRoots[0]; $path=Join-Path $root 'smoke-result.json'; $hash=(Get-FileHash -LiteralPath $path).Hash
        $handle=[IO.File]::Open((Join-Path $root 'smoke-run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            $options=New-TestOptions Run E02; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath
            $options.AllowExplorerUiChanges=$true; $options.TestRoot=$root
            $result=Invoke-ExplorerSmoke $options $adapter
            Assert ($result.Status -eq 'Blocked' -and $state.Cli -eq 0 -and (Get-FileHash -LiteralPath $path).Hash -eq $hash)
        } finally { $handle.Dispose() }
    }
    Test 'missing human visual review never marks an E2E case Passed' {
        $root=$ownedRoots[0]; $path=Join-Path $root 'smoke-result.json'
        $previous=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json; $previous.Status='AwaitingVisualReview'; Write-SmokeJson $path $previous
        $hash=(Get-FileHash -LiteralPath $path).Hash
        $options=New-TestOptions Confirm E02; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath; $options.TestRoot=$root
        $result=Invoke-ExplorerSmoke $options $adapter
        Assert ($result.Status -eq 'Blocked' -and (Get-FileHash -LiteralPath $path).Hash -eq $hash)
    }
    foreach ($caseName in @('E01','E02')) {
        Test "$caseName synthetic orchestration validates CLI sequence and ends AwaitingVisualReview, never live Passed" {
            $fixtureCase=$caseName
            $prepare=New-TestOptions Prepare $caseName; $prepare.ConfirmIsolatedSession=$true; $prepare.SessionEvidence=$evidencePath
            $prepared=Invoke-ExplorerSmoke $prepare $adapter
            [void]$ownedRoots.Add($prepared.TestRoot); Assert ($prepared.Status -eq 'Prepared')
            $folder=Join-Path $prepared.TestRoot $caseName
            $a=Join-Path $folder 'A'; $b=Join-Path $folder 'B'; $c=Join-Path $folder 'C'
            $original=New-TestObservation @((New-TestView OA 10 $a),(New-TestView OB 10 $b),(New-TestView OC 20 $c))
            $after=New-TestObservation @($original.Views+(New-TestView NA 30 $a)+(New-TestView NB 30 $b)+(New-TestView NC 40 $c))
            $aOnly=New-TestObservation @((New-TestView A 30 $a))
            $ab=New-TestObservation @($aOnly.Views+(New-TestView B 30 $b))
            $observations=@($original,$original,$original,$after)
            if ($caseName -eq 'E02') { $observations=@($empty,$aOnly,$aOnly,$ab) }
            $routing=@{ Index=0; Actions=@(); Parent=$null; Child=$null }
            $writeJson=${function:Write-SmokeJson}
            $routingAdapter=@{ Facts=$adapter.Facts; Uia=$adapter.Uia
                Observe={ $value=$observations[$routing.Index]; $routing.Index++; $value }.GetNewClosure()
                Cli={
                    param($arguments,$prefix)
                    $action=$arguments[1]; $routing.Actions+=$action
                    if ($action -eq 'Capture') {
                        $snapshot=[pscustomobject]@{ Version=1; Windows=@(@{ Paths=@($a,$b) },@{ Paths=@($c) }) }
                        & $writeJson $arguments[3] $snapshot -New
                    } elseif ($action -eq 'Restore') {
                        $snapshot=Get-Content -LiteralPath $arguments[3] -Raw | ConvertFrom-Json
                        $items=@(); $g=0
                        foreach ($group in $snapshot.Windows) {
                            $g++; $i=0
                            foreach ($path in $group.Paths) {
                                $i++; $view=@($after.Views | Where-Object { $_.Path -eq $path -and $_.RootHwnd -in @(30,40) })[0]
                                $status='Verified'
                                if ($fixtureCase -eq 'E02' -and $i -eq 2) { $status='SkippedInvalidPath' }
                                $items+=[pscustomobject]@{ GroupIndex=$g; ItemIndex=$i; RequestedPath=$path; Status=$status
                                    WindowFingerprint=$view.Fingerprint; WindowCreateAttempted=($i -eq 1); InvokeAttempted=$false; NavigateAttempted=$false }
                            }
                        }
                        $report=[pscustomobject]@{ SchemaVersion=1; State='Completed'; RunId='synthetic-parent'; RootRunId='synthetic-parent'
                            ParentRunId=$null; RootReportPath=$arguments[5]; SourceSnapshotHash=(Get-FileHash -LiteralPath $arguments[3]).Hash; Items=$items }
                        $routing.Parent=$report; & $writeJson $arguments[5] $report -New
                    } elseif ($action -eq 'PreviewRetry') {
                        $preview=[pscustomobject]@{ RunId=$routing.Parent.RunId; ReportHash=(Get-FileHash -LiteralPath $arguments[3]).Hash; Targets=@($aOnly.Views[0].Fingerprint) }
                        & $writeJson ($arguments[3]+'.retry-preview.json') $preview -New
                    } elseif ($action -eq 'Retry') {
                        if ($arguments -contains '-IncludeUncertain') { throw 'Unexpected uncertain retry' }
                        $directory=Join-Path $folder 'RetryRuns'; [void][IO.Directory]::CreateDirectory($directory)
                        $item=[pscustomobject]@{ GroupIndex=1; ItemIndex=2; RequestedPath=$b; Status='Verified'; WindowFingerprint=$aOnly.Views[0].Fingerprint }
                        $child=[pscustomobject]@{ SchemaVersion=1; State='Completed'; ParentRunId=$routing.Parent.RunId; RootRunId=$routing.Parent.RootRunId
                            RootReportPath=$routing.Parent.RootReportPath; SourceSnapshotHash=$routing.Parent.SourceSnapshotHash; Items=@($item) }
                        & $writeJson (Join-Path $directory 'synthetic-child.json') $child -New
                    }
                    return 0
                }.GetNewClosure()
            }
            $run=New-TestOptions Run $caseName; $run.ConfirmIsolatedSession=$true; $run.SessionEvidence=$evidencePath
            $run.TestRoot=$prepared.TestRoot; $run.AllowExplorerUiChanges=$true
            $result=Invoke-ExplorerSmoke $run $routingAdapter
            Assert ($result.Status -eq 'AwaitingVisualReview') ($result.Reason + ' ' + (ConvertTo-Json -InputObject $routing.Parent -Depth 8 -Compress))
            $expected='Capture,Preview,Restore'; if ($caseName -eq 'E02') { $expected='Restore,PreviewRetry,Retry' }
            Assert (($routing.Actions -join ',') -eq $expected -and $result.Commands.Count -eq 3)
            Assert ($result.($fixtureCase) -eq 'AwaitingVisualReview') 'Mocked orchestration must not claim live success'
            $otherCase='E02'; if ($fixtureCase -eq 'E02') { $otherCase='E01' }
            Assert ($result.$otherCase -eq 'NotRun')
            Assert ($result.After.Views.Count -eq $(if ($caseName -eq 'E01') { 6 } else { 2 }))
        }
    }
    Test 'CLI failure stops after exactly one call and does not automatically replay' {
        $prepare=New-TestOptions Prepare E02; $prepare.ConfirmIsolatedSession=$true; $prepare.SessionEvidence=$evidencePath
        $prepared=Invoke-ExplorerSmoke $prepare $adapter; [void]$ownedRoots.Add($prepared.TestRoot)
        $failureState=@{ Calls=0 }; $failureAdapter=$adapter.Clone()
        $failureAdapter.Cli={ param($arguments,$prefix) $failureState.Calls++; return 42 }.GetNewClosure()
        $run=New-TestOptions Run E02; $run.ConfirmIsolatedSession=$true; $run.SessionEvidence=$evidencePath
        $run.TestRoot=$prepared.TestRoot; $run.AllowExplorerUiChanges=$true
        $result=Invoke-ExplorerSmoke $run $failureAdapter
        Assert ($result.Status -eq 'Failed' -and $failureState.Calls -eq 1 -and $result.Commands[0].ExitCode -eq 42)
        $second=Invoke-ExplorerSmoke $run $failureAdapter
        Assert ($second.Status -eq 'Blocked' -and $failureState.Calls -eq 1)
    }
    Test 'automated Verify rejects changed live scope and preserves pending result without CLI calls' {
        $root=$ownedRoots[2]; $path=Join-Path $root 'smoke-result.json'
        $pending=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $hash=(Get-FileHash -LiteralPath $path).Hash
        $changed=New-TestObservation @($pending.After.Views[0]) # B is absent.
        $verificationAdapter=$adapter.Clone(); $verificationAdapter.Observe={ $changed }.GetNewClosure()
        $options=New-TestOptions Verify E02; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath; $options.TestRoot=$root
        $calls=$state.Cli
        $result=Invoke-ExplorerSmoke $options $verificationAdapter
        Assert ($result.Status -eq 'Blocked' -and $state.Cli -eq $calls -and (Get-FileHash -LiteralPath $path).Hash -eq $hash)
    }
    Test 'automated Verify rechecks evidence and records visual NotRun without inventing operator approval' {
        $root=$ownedRoots[2]; $path=Join-Path $root 'smoke-result.json'
        $pending=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $verificationAdapter=$adapter.Clone(); $observation=$pending.After
        $verificationAdapter.Observe={ $observation }.GetNewClosure()
        $options=New-TestOptions Verify E02; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath; $options.TestRoot=$root
        $calls=$state.Cli
        $result=Invoke-ExplorerSmoke $options $verificationAdapter
        Assert ($result.Status -eq 'Passed' -and $result.VisualReview -eq 'NotRun' -and $null -eq $result.VisualEvidence -and $state.Cli -eq $calls) $result.Reason
        $hash=(Get-FileHash -LiteralPath $path).Hash
        $again=Invoke-ExplorerSmoke $options $verificationAdapter
        Assert ($again.Status -eq 'Blocked' -and (Get-FileHash -LiteralPath $path).Hash -eq $hash)
    }
    Test 'changed JSON evidence blocks both visual and automated confirmation and preserves pending result' {
        $root=$ownedRoots[1]; $resultPath=Join-Path $root 'smoke-result.json'
        $pending=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $artifact=Join-Path $root $pending.EvidenceHashes[0].RelativePath
        [IO.File]::AppendAllText($artifact,' ')
        $before=(Get-FileHash -LiteralPath $resultPath).Hash
        $options=New-TestOptions Confirm E01; $options.ConfirmIsolatedSession=$true; $options.SessionEvidence=$evidencePath
        $options.TestRoot=$root; $options.ConfirmVisibleAndGrouping=$true; $options.VisualEvidence='Synthetic negative fixture, not real GUI review.'
        foreach ($mode in @('Confirm','Verify')) {
            $options.Mode=$mode
            $result=Invoke-ExplorerSmoke $options $adapter
            Assert ($result.Status -eq 'Blocked' -and $result.Reason -eq 'EvidenceChanged')
            Assert ((Get-FileHash -LiteralPath $resultPath).Hash -eq $before)
        }
    }
} finally {
    [IO.File]::Delete($evidencePath)
    foreach ($root in $ownedRoots) {
        Assert ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($root)) -ieq [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\'))
        Assert ([IO.Path]::GetFileName($root) -match '^ResumeExplorer-E2E-[a-f0-9]{32}$')
        # Offline-created synthetic directories only; the real runner never cleans up any fixture.
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
Test 'public entry defaults and dot-source import cannot perform GUI actions' {
    $entry=Join-Path $PSScriptRoot 'Integration\Invoke-ExplorerSmoke.ps1'; $engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -Sta -File $entry
    Assert ($LASTEXITCODE -eq 2); $result=($json -join "`n") | ConvertFrom-Json
    Assert ($result.Status -eq 'NotRun' -and $result.Commands.Count -eq 0 -and $null -eq $result.Facts)
    $import=@(& $engine -NoProfile -Sta -Command ". '$($entry.Replace("'","''"))'; 'ImportedWithoutDispatch'")
    Assert ($LASTEXITCODE -eq 0 -and ($import -join '') -eq 'ImportedWithoutDispatch')
}
Write-Host "$script:passed smoke harness tests passed. E01/E02 live status: NotRun. No Explorer actions performed."
