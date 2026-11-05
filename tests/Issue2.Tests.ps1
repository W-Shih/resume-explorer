# Deterministic adapter tests. No Explorer, UIA, network or Pester dependency.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'resume-explorer.core.ps1')
. (Join-Path $PSScriptRoot 'Fixtures/IsolatedCli.ps1')
$script:passed=0
function Assert($Condition, $Message='Assertion failed') { if (-not $Condition) { throw $Message } }
function Test($Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Host "PASS $Name"
}
function Assert-Throws([scriptblock]$Body) {
    $thrown=$false
    try { & $Body } catch { $thrown=$true }
    Assert $thrown 'Expected rejection'
}
function New-Fixture([string]$Mode='Normal', [int]$Delay=0) {
    $state=@{ Time=0; Invokes=0; Navigates=0; Opens=0; Checkpoints=0; Sleeps=@(); DetectionStart=0; Mode=$Mode; Delay=$Delay; Reads=0 }
    $config=@{ DetectionTimeoutSeconds=15; PollIntervalMs=200; TransientErrorBackoffMs=@(200,400,800)
        StableDurationMs=600; BaselineTimeoutSeconds=3; NavigationTimeoutSeconds=10 }
    $fp=[pscustomobject]@{ Hwnd=10L; RootHwnd=10L; PID=42; ProcessStartedAtUtc='2026-11-01T00:00:00Z'; SessionId=1 }
    $observe={
        $view={ param($id,$path='C:\old') [pscustomobject]@{ Identity=$id; RawHwnd=10L; RootHwnd=10L; PID=42; Path=$path; PathReadable=$true; Fingerprint=$fp; ComObject=$null } }
        $views=@((& $view 'B')); $reliable=$true; $errors=@()
        if ($state.Invokes -gt 0) {
            $state.Reads++; $elapsed=$state.Time-$state.DetectionStart
            if ($state.Mode -eq 'Errors' -and $state.Reads -le 5) { $reliable=$false }
            elseif ($state.Mode -eq 'LateRecovery' -and $elapsed -lt 8000) { $reliable=$false }
            elseif ($state.Mode -eq 'ForeverErrors') { $reliable=$false }
            elseif ($state.Mode -eq 'ResetErrors' -and $state.Reads -in @(1,2,4)) { $reliable=$false }
            if (-not $reliable) { $errors=@([pscustomobject]@{ Stage='Identity'; Message='temporary'; HResult=-1 }) }
            if ($state.Mode -ne 'Timeout' -and $elapsed -ge $state.Delay) {
                $id='A'
                if ($state.Mode -eq 'Replace' -and $elapsed -ge 400) { $id='C' }
                $path='C:\home'
                if ($state.Navigates -gt 0 -and $state.Mode -ne 'NavigationTimeout') { $path='C:\target' }
                $views+= & $view $id $path
                if ($state.Mode -eq 'Duplicate') { $views+= & $view $id $path }
                if ($state.Mode -eq 'Multiple' -or ($state.Mode -eq 'MultipleThenSingle' -and $elapsed -eq 0)) { $views+= & $view 'C' }
                if ($state.Mode -eq 'BaselineGone') { $views=@($views | Where-Object { $_.Identity -ne 'B' }) }
            }
        } elseif ($state.Mode -eq 'UnstableBaseline') { $reliable=$false }
        if ($state.Mode -eq 'ExistingTarget') { $views[0].Path='C:\target' }
        [pscustomobject]@{ Views=$views; EnumerationSucceeded=$true; IdentitySetReliable=$reliable; ReadErrors=$errors
            ObservedAtUtc='fixture'; RawCount=$views.Count; UniqueCount=@($views.Identity | Select-Object -Unique).Count }
    }.GetNewClosure()
    $adapter=@{
        Now={ $state.Time }.GetNewClosure()
        Sleep={ param($ms) $state.Sleeps+= $ms; $state.Time+=$ms }.GetNewClosure()
        Fingerprint={ param($hwnd) if ($state.Mode -eq 'WindowGone' -and $state.Invokes) { throw 'gone' }; $fp }.GetNewClosure()
        Observe=$observe
        PrepareInvoke={ param($hwnd) if ($state.Mode -eq 'NoControl') { throw 'missing' }; 'pattern' }.GetNewClosure()
        Invoke={ param($pattern) $state.Invokes++; $state.DetectionStart=$state.Time; if ($state.Mode -eq 'InvokeThrows') { throw 'uncertain' } }.GetNewClosure()
        Navigate={ param($view,$path) if ($view.Identity -ne 'A') { throw 'Wrong navigation target' }; $state.Navigates++; if ($state.Mode -eq 'NavigateThrows') { throw 'uncertain' } }.GetNewClosure()
        PathExists={ param($path) $path -ne 'invalid' }
        OpenWindow={ param($path) $state.Opens++ }.GetNewClosure()
    }
    $checkpoint={ $state.Checkpoints++; if ($state.Mode -eq 'CheckpointFails') { throw 'disk full' } }.GetNewClosure()
    @{ State=$state; Config=$config; Adapter=$adapter; Fingerprint=$fp; Checkpoint=$checkpoint; Item=(New-RestoreItem 2 3 'C:\target') }
}
function Run-Fixture($Fixture) {
    Invoke-TabTransaction $Fixture.Item $Fixture.Adapter $Fixture.Fingerprint $Fixture.Config $Fixture.Checkpoint
}

Test 'normal transaction invokes and navigates exactly once' {
    $f=New-Fixture; Run-Fixture $f
    Assert ($f.Item.Status -eq 'Verified') $f.Item.Error; Assert ($f.State.Invokes -eq 1); Assert ($f.State.Navigates -eq 1)
}
Test '12 second delayed exposure uses only observations' {
    $f=New-Fixture Normal 12000; Run-Fixture $f
    Assert ($f.Item.Status -eq 'Verified'); Assert ($f.State.Invokes -eq 1)
    Assert ($f.Item.Diagnostics.DetectionElapsedMs -eq 12600)
}
Test 'timeout does not repeat Invoke or navigate' {
    $f=New-Fixture Timeout; Run-Fixture $f
    Assert ($f.Item.Status -eq 'OutcomeUnknown'); Assert ($f.State.Invokes -eq 1); Assert ($f.State.Navigates -eq 0)
    Assert ($f.Item.Diagnostics.DetectionElapsedMs -eq 15000)
}
Test 'same identity duplicate rows are not ambiguous' {
    $f=New-Fixture Duplicate; Run-Fixture $f
    Assert ($f.Item.Status -eq 'Verified'); Assert (@($f.Item.Diagnostics.Samples | Where-Object { $_.Phase -eq 'Detection' })[0].RawCount -eq 3)
}
foreach ($mode in @('Multiple','MultipleThenSingle','Replace','BaselineGone','WindowGone')) {
    Test "unsafe $mode stops without Navigate" {
        $f=New-Fixture $mode; Run-Fixture $f
        Assert ($f.State.Invokes -eq 1); Assert ($f.State.Navigates -eq 0); Assert ($f.Item.Status -eq 'OutcomeUnknown')
    }
}
Test 'candidate history cannot forget a vanished candidate' {
    $seen=@{}; $a=[pscustomobject]@{ Identity='A' }; $c=[pscustomobject]@{ Identity='C' }; $b=[pscustomobject]@{ Identity='B' }
    $first=Resolve-NewTabCandidate @('B') @($b,$a,$c) $seen
    $second=Resolve-NewTabCandidate @('B') @($b,$a) $seen
    Assert ($first.State -eq 'Ambiguous' -and $second.State -eq 'Ambiguous' -and $seen.Count -eq 2)
}
Test 'unstable baseline never invokes' {
    $f=New-Fixture UnstableBaseline; Run-Fixture $f
    Assert ($f.Item.Status -eq 'PreconditionFailed'); Assert ($f.State.Invokes -eq 0)
}
Test 'missing control never invokes' {
    $f=New-Fixture NoControl; Run-Fixture $f
    Assert ($f.Item.Status -eq 'PreconditionFailed'); Assert ($f.State.Invokes -eq 0)
}
Test 'five read errors use capped backoff then recover' {
    $f=New-Fixture Errors; Run-Fixture $f
    $delays=@($f.State.Sleeps | Select-Object -Skip 3 -First 5)
    Assert (($delays -join ',') -eq '200,400,800,800,800') ($delays -join ',')
    Assert ($f.Item.Status -eq 'Verified'); Assert ($f.Item.Diagnostics.TransientReadErrorCount -eq 5)
}
Test 'more than three errors recover after 8 seconds' {
    $f=New-Fixture LateRecovery; Run-Fixture $f
    Assert ($f.Item.Status -eq 'Verified'); Assert ($f.Item.Diagnostics.TransientReadErrorCount -gt 3); Assert ($f.State.Invokes -eq 1)
}
Test 'errors reset streak after reliable sample' {
    $f=New-Fixture ResetErrors 2000; Run-Fixture $f
    $delays=@($f.State.Sleeps | Select-Object -Skip 3 -First 4)
    Assert (($delays -join ',') -eq '200,400,200,200')
}
Test 'permanent read errors consume one deadline with clipped final sleep' {
    $f=New-Fixture ForeverErrors; Run-Fixture $f
    Assert ($f.Item.Diagnostics.DetectionElapsedMs -eq 15000); Assert ($f.State.Navigates -eq 0)
    Assert ($f.Item.ReasonCode -eq 'ObservationIncomplete')
}
Test '14.8 second candidate cannot extend stability beyond deadline' {
    $f=New-Fixture Normal 14800; Run-Fixture $f
    Assert ($f.Item.Diagnostics.DetectionElapsedMs -eq 15000); Assert ($f.State.Navigates -eq 0)
}
Test 'configurable 5 and 20 second deadlines' {
    foreach ($seconds in @(5,20)) {
        $f=New-Fixture Timeout; $f.Config.DetectionTimeoutSeconds=$seconds; Run-Fixture $f
        Assert ($f.Item.Diagnostics.DetectionElapsedMs -eq 1000*$seconds)
    }
}
Test 'invalid configuration rejected' {
    foreach ($key in @('DetectionTimeoutSeconds','PollIntervalMs','StableDurationMs','BaselineTimeoutSeconds','NavigationTimeoutSeconds')) {
        $f=New-Fixture; $f.Config[$key]=0; Assert-Throws { Assert-RestoreConfig $f.Config }
    }
    foreach ($value in @(@(),@(0),@(-1))) { $f=New-Fixture; $f.Config.TransientErrorBackoffMs=$value; Assert-Throws { Assert-RestoreConfig $f.Config } }
}
Test 'Invoke exception reconciles but never navigates' {
    $f=New-Fixture InvokeThrows; Run-Fixture $f
    Assert ($f.Item.ReasonCode -eq 'InvokeOutcomeUnknown'); Assert ($f.State.Invokes -eq 1); Assert ($f.State.Navigates -eq 0)
}
Test 'navigation exception never resends' {
    $f=New-Fixture NavigateThrows; Run-Fixture $f
    Assert ($f.Item.ReasonCode -eq 'NavigationException'); Assert ($f.State.Navigates -eq 1)
}
Test 'old matching path cannot verify candidate' {
    $f=New-Fixture NavigationTimeout
    $original=$f.Adapter.Observe
    $f.Adapter.Observe={ $obs=& $original; $obs.Views[0].Path='C:\target'; $obs }.GetNewClosure()
    Run-Fixture $f
    Assert ($f.Item.ReasonCode -eq 'NavigationTimeout'); Assert ($f.State.Navigates -eq 1)
}
Test 'checkpoint failure prevents Invoke' {
    $f=New-Fixture CheckpointFails; Assert-Throws { Run-Fixture $f }
    Assert ($f.State.Invokes -eq 0); Assert ($f.State.Navigates -eq 0)
}
Test 'group stop preserves current and remaining items' {
    $f=New-Fixture Multiple
    $items=@((New-RestoreItem 2 1 'C:\target'),(New-RestoreItem 2 2 'C:\target'),(New-RestoreItem 2 3 'invalid'))
    $run=New-Run $items 'hash' 'source' $null
    Invoke-RestoreGroups $run $f.Adapter $f.Config $f.Checkpoint $f.Fingerprint
    Assert ($items[0].Status -eq 'OutcomeUnknown'); Assert ($items[1].Status -eq 'NotAttempted'); Assert ($items[2].Status -eq 'SkippedInvalidPath')
    Assert ($f.State.Invokes -eq 1)
}
Test 'group failure does not block next group' {
    $f=New-Fixture Multiple
    $items=@((New-RestoreItem 2 1 'C:\target'),(New-RestoreItem 3 1 'C:\target'))
    $run=New-Run $items 'hash' 'source' $null
    $cp={ if ($items[0].ReasonCode -eq 'AmbiguousCandidates' -and -not $f.State.ResetDone) { $f.State.Mode='Normal'; $f.State.Invokes=0; $f.State.Navigates=0; $f.State.ResetDone=$true } }.GetNewClosure()
    Invoke-RestoreGroups $run $f.Adapter $f.Config $cp $f.Fingerprint
    Assert ($items[0].Status -eq 'OutcomeUnknown'); Assert ($items[1].Status -eq 'Verified')
}
Test 'path comparison preserves roots and supports trailing separators' {
    Assert (Test-PathEqual 'C:\' 'c:\'); Assert (Test-PathEqual 'C:\foo\' 'c:\FOO')
    Assert (Test-PathEqual '\\server\share\' '\\SERVER\SHARE')
    Assert (-not (Test-PathEqual 'C:\foo' 'C:\foobar'))
}
Test 'fingerprint refuses process replacement' {
    $f=New-Fixture; $other=$f.Fingerprint | Select-Object *; $other.ProcessStartedAtUtc='other'
    Assert (-not (Test-FingerprintEqual $f.Fingerprint $other))
}
Test 'retry selection requires explicit uncertainty and preserves indices' {
    $item=New-RestoreItem 2 3 'C:\target'; $item.Status='OutcomeUnknown'; $item.InvokeAttempted=$true
    $source=New-Run @($item) 'hash' 'source' $null
    Assert-Throws { Select-RetryItems $source 2 @(3) $false @() }
    $selected=@(Select-RetryItems $source 2 @(3) $true @())
    Assert ($selected[0].ItemIndex -eq 3 -and $selected[0].GroupIndex -eq 2)
    Assert-Throws { Select-RetryItems $source 2 @(3,3) $true @() }
    Assert-Throws { Select-RetryItems $source 2 @(99) $true @() }
    $item.Status='Verified'; Assert-Throws { Select-RetryItems $source 2 @(3) $true @() }
}
Test 'completed child blocks replay; crashed child needs explicit uncertainty' {
    $item=New-RestoreItem 2 3 'C:\target'; $child=New-RestoreItem 2 3 'C:\target'
    $source=New-Run @($item) 'hash' 'source' $null
    $child.Status='Verified'; Assert-Throws { Select-RetryItems $source 2 @(3) $true @($child) }
    $child.Status='NotAttempted'; $child.InvokeAttempted=$true
    Assert-Throws { Select-RetryItems $source 2 @(3) $false @($child) }
}
Test 'atomic checkpoint survives repeated replacement and excludes COM objects' {
    $directory=Join-Path $env:TEMP ('resume-explorer-tests-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try {
        $f=New-Fixture; Run-Fixture $f
        $run=New-Run @($f.Item) 'hash' 'source' $null
        $path=Initialize-RunPath $run (Join-Path $directory 'run.json')
        Write-RestoreCheckpoint $run $path
        $read=Read-RunReport $path
        Assert ($read.Items[0].Status -eq 'Verified')
        Assert (-not ((Get-Content -LiteralPath $path -Raw).Contains('ComObject')))
        Assert-Throws { Initialize-RunPath $run $path }
    } finally { Get-ChildItem -LiteralPath $directory -File | Remove-Item; [IO.Directory]::Delete($directory) }
}
Test 'new window duplicate views are one root window' {
    $f=New-Fixture; $original=$f.Adapter.Observe
    $f.Adapter.Observe={ $obs=& $original; $obs.Views+= $obs.Views[0]; $obs }.GetNewClosure()
    $diagnostics=New-DetectionDiagnostics $f.Config
    $result=Wait-NewExplorerWindow $f.Adapter @() 'C:\old' $f.Config $diagnostics
    Assert ($result.Reason -eq 'Verified')
}
Test 'new window ambiguity never selects the first candidate' {
    $f=New-Fixture; $original=$f.Adapter.Observe
    $f.Adapter.Observe={
        $obs=& $original; $second=$obs.Views[0] | Select-Object *; $second.RootHwnd=20L; $second.RawHwnd=20L
        $obs.Views+= $second; $obs
    }.GetNewClosure()
    $result=Wait-NewExplorerWindow $f.Adapter @() 'C:\old' $f.Config (New-DetectionDiagnostics $f.Config)
    Assert ($result.Reason -eq 'WindowAmbiguous'); Assert ($f.State.Invokes -eq 0)
}
Test 'incomplete sample resets candidate continuous stability' {
    $f=New-Fixture; $original=$f.Adapter.Observe
    $f.Adapter.Observe={
        $obs=& $original
        if ($f.State.Invokes -gt 0 -and $f.State.Reads -eq 3) { $obs.IdentitySetReliable=$false }
        $obs
    }.GetNewClosure()
    Run-Fixture $f
    Assert ($f.Item.Status -eq 'Verified'); Assert ($f.Item.Diagnostics.DetectionElapsedMs -eq 1200)
}
Test 'temporary enumeration failure follows observation backoff' {
    $f=New-Fixture; $original=$f.Adapter.Observe
    $f.Adapter.Observe={
        $obs=& $original
        if ($f.State.Invokes -gt 0 -and $f.State.Reads -le 4) { $obs.IdentitySetReliable=$false; $obs.EnumerationSucceeded=$false }
        $obs
    }.GetNewClosure()
    Run-Fixture $f
    Assert ($f.Item.Status -eq 'Verified'); Assert ($f.Item.Diagnostics.TransientReadErrorCount -eq 4)
}
Test 'complete run writes checkpoints in script scope and child family is discoverable' {
    $directory=Join-Path $env:TEMP ('resume-explorer-tests-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try {
        $f=New-Fixture; $root=New-Run @($f.Item) 'hash' 'snapshot' $null
        $path=Initialize-RunPath $root (Join-Path $directory 'root.json')
        Complete-Run $root $path $f.Adapter $f.Config $f.Fingerprint
        $read=Read-RunReport $path
        Assert ($read.State -eq 'Completed' -and $read.Items[0].Status -eq 'Verified')
        $childItem=New-RestoreItem 2 5 'C:\target'; $childItem.Status='Verified'
        $child=New-Run @($childItem) 'hash' 'snapshot' $root.RunId
        $child.RootRunId=$root.RunId; $child.RootReportPath=$path
        $childPath=Initialize-RunPath $child (Join-Path $directory 'RetryRuns\child.json')
        [IO.File]::WriteAllText(($childPath+'.retry-preview.json'),'{}')
        $found=@(Get-RetryDescendantItems $root $path)
        Assert ($found.Count -eq 1 -and $found[0].ItemIndex -eq 5)
        $found=@(Get-RetryDescendantItems $child $childPath)
        Assert ($found.Count -eq 1) 'A child report must also see the whole family'
    } finally {
        $resolved=[IO.Path]::GetFullPath($directory)
        Assert ($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP)) -and (Split-Path $resolved -Leaf).StartsWith('resume-explorer-tests-'))
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Test 'global Shell failure aborts all remaining groups and persists last boundary' {
    $directory=Join-Path $env:TEMP ('resume-explorer-tests-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try {
        $f=New-Fixture; $original=$f.Adapter.Observe
        $f.Adapter.Observe={
            $obs=& $original
            if ($f.State.Invokes -gt 0) { $obs | Add-Member NoteProperty GlobalUnavailable $true }
            $obs
        }.GetNewClosure()
        $run=New-Run @((New-RestoreItem 1 1 'C:\target'),(New-RestoreItem 2 1 'C:\target')) 'hash' 'source' $null
        $path=Initialize-RunPath $run (Join-Path $directory 'run.json')
        Assert-Throws { Complete-Run $run $path $f.Adapter $f.Config $f.Fingerprint }
        $read=Read-RunReport $path
        Assert ($read.State -eq 'Aborted'); Assert ($read.Items[0].InvokeAttempted)
        Assert ($read.Items[1].Status -eq 'NotAttempted'); Assert ($f.State.Invokes -eq 1)
    } finally { Get-ChildItem -LiteralPath $directory -File | Remove-Item; [IO.Directory]::Delete($directory) }
}
Test 'snapshot Capture and Preview preserve groups and duplicate paths' {
    $directory=Join-Path $env:TEMP ('resume-explorer-tests-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try {
        function Get-ExplorerObservation {
            [pscustomobject]@{ IdentitySetReliable=$true; Views=@(
                [pscustomobject]@{ RawHwnd=10; Path=$directory; PathReadable=$true },
                [pscustomobject]@{ RawHwnd=10; Path=$directory; PathReadable=$true },
                [pscustomobject]@{ RawHwnd=20; Path=$directory; PathReadable=$true }
            ) }
        }
        $path=Join-Path $directory 'snapshot.json'; Save-Snapshot $path
        $data=Read-Snapshot $path
        Assert ($data.Windows.Count -eq 2 -and $data.Windows[0].Paths.Count -eq 2)
        $before=(Get-FileHash -LiteralPath $path).Hash
        # New guard would otherwise open the real user's anchor. Preserve Preview/hash assertions.
        $isolatedCli=New-IsolatedTestCli $directory
        & $isolatedCli -Action Preview -Snapshot $path
        Assert ((Get-FileHash -LiteralPath $path).Hash -eq $before)
    } finally { Get-ChildItem -LiteralPath $directory -File | Remove-Item; [IO.Directory]::Delete($directory) }
}
Test 'PreviewRetry and Retry integrate with preview fingerprints and child replay prevention' {
    $directory=Join-Path $env:TEMP ('resume-explorer-tests-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try {
        $f=New-Fixture
        function New-ExplorerAdapter { $f.Adapter }
        $root=New-Run @((New-RestoreItem 2 3 'C:\target')) 'hash' 'snapshot' $null
        $path=Initialize-RunPath $root (Join-Path $directory 'root.json')
        Show-RetryPreview $path
        Start-RetryRun -ReportPath $path -GroupIndex 2 -TargetHwnd 10 -ItemIndexes @(3) -Config $f.Config
        Assert ($f.State.Invokes -eq 1 -and $f.State.Navigates -eq 1)
        $children=@(Get-RetryDescendantItems $root $path)
        Assert ($children.Count -eq 1 -and $children[0].Status -eq 'Verified')
        Assert-Throws { Start-RetryRun -ReportPath $path -GroupIndex 2 -TargetHwnd 10 -ItemIndexes @(3) -Config $f.Config }
        Assert ($f.State.Invokes -eq 1)
    } finally {
        $resolved=[IO.Path]::GetFullPath($directory)
        Assert ($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP)) -and (Split-Path $resolved -Leaf).StartsWith('resume-explorer-tests-'))
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Test 'production OpenWindow adapter explicitly requests a visible Explorer window' {
    $launches=New-Object System.Collections.ArrayList
    function Start-Process {
        param([string]$FilePath, [string]$ArgumentList, [string]$WindowStyle)
        [void]$launches.Add([pscustomobject]@{ FilePath=$FilePath; ArgumentList=$ArgumentList; WindowStyle=$WindowStyle })
    }
    # Exercise the production adapter, rather than replacing OpenWindow with a fake.
    $adapter=New-ExplorerAdapter
    & $adapter.OpenWindow 'C:\folder with spaces'
    Assert ($launches.Count -eq 1) 'One request must launch Explorer exactly once'
    Assert ($launches[0].FilePath -eq "$env:WINDIR\explorer.exe")
    Assert ($launches[0].ArgumentList -ceq '"C:\folder with spaces"')
    Assert ($launches[0].WindowStyle -eq 'Normal') 'Restore must request visible windows; Hidden caused the Verified-but-invisible regression'
}
Write-Host "$script:passed adapter tests passed. No live Explorer actions performed."
