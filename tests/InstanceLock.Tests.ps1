# Real OS file sharing and unchanged CLI copies. All anchors/data/processes owned by this suite.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$core=Join-Path $root 'resume-explorer.core.ps1'
. $core
. (Join-Path $PSScriptRoot 'Fixtures/IsolatedCli.ps1')
$engine=(Get-Process -Id $PID).Path
$worker=Join-Path $PSScriptRoot 'Fixtures/InstanceLock.Worker.ps1'
$storage=Join-Path ([IO.Path]::GetTempPath()) ('ResumeExplorer-LockTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($storage)
$children=[Collections.Generic.List[object]]::new()
$passed=0
function Assert($Condition,$Message='Instance lock assertion failed') { if (-not $Condition) { throw $Message } }
function Test($Name,$Body) { & $Body; $script:passed++; Write-Host "PASS $Name" }
function New-Case {
    $dir=Join-Path $storage ([guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($dir)
    @{ Directory=$dir; Anchor=(Join-Path $dir 'instance.lock'); Ready=(Join-Path $dir 'ready')
        Release=(Join-Path $dir 'release'); Gate=(Join-Path $dir 'gate'); Acquired=(Join-Path $dir 'acquired') }
}
function Wait-Until($Condition,[string]$Description) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while (-not (& $Condition)) {
        if ($clock.Elapsed.TotalSeconds -gt 25) { throw "TestTimeout: $Description" }
        Start-Sleep -Milliseconds 20
    }
}
function Start-Child([string[]]$Arguments,[string]$Directory=$storage,[string]$CmdScript='') {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$engine; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false); $info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    $info.WorkingDirectory=$Directory
    if ($CmdScript) {
        $info.FileName=$env:ComSpec
        # cmd /c requires this outer pair of quotes; script path is a controlled test fixture.
        $info.Arguments='/d /c ""'+$CmdScript+'""'
    } else { foreach ($arg in @('-NoProfile','-NonInteractive')+$Arguments) { $info.ArgumentList.Add($arg) } }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
    if (-not $process.Start()) { throw 'ChildStartFailed' }
    $child=@{ Process=$process; Out=$process.StandardOutput.ReadToEndAsync(); Err=$process.StandardError.ReadToEndAsync() }
    $children.Add($child)
    $child
}
function Finish-Child($Child) {
    Wait-Until { $Child.Process.HasExited } ('child '+$Child.Process.Id)
    @{ Code=$Child.Process.ExitCode; Text=($Child.Out.GetAwaiter().GetResult()+$Child.Err.GetAwaiter().GetResult()) }
}
function Start-Worker($Fixture,[string]$Mode='Hold',[string]$Directory=$storage) {
    Start-Child @('-File',$worker,'-Core',$core,'-Anchor',$Fixture.Anchor,'-Mode',$Mode,
        '-Ready',$Fixture.Ready,'-Release',$Fixture.Release,'-Gate',$Fixture.Gate,'-Acquired',$Fixture.Acquired) $Directory
}
function Start-Holder($Fixture) {
    $child=Start-Worker $Fixture
    Wait-Until { [IO.File]::Exists($Fixture.Ready) -or $child.Process.HasExited } 'holder ready'
    Assert (-not $child.Process.HasExited) 'Holder exited before readiness'
    Assert ([IO.File]::ReadAllText($Fixture.Ready) -eq [string]$child.Process.Id) 'Ready PID differs from owned child'
    $child
}
function Release-Holder($Fixture,$Child) {
    [IO.File]::WriteAllText($Fixture.Release,'release')
    $r=Finish-Child $Child; Assert ($r.Code -eq 0) $r.Text
}
function Assert-Reacquire($Path) {
    $handle=Enter-ResumeExplorerInstanceLock $Path
    try { Assert ($handle -is [IO.FileStream]) } finally { $handle.Dispose() }
}
function Assert-LockError($Path,[string]$Prefix) {
    $caught=$null
    try { $handle=Enter-ResumeExplorerInstanceLock $Path; $handle.Dispose() } catch { $caught=$_.Exception }
    Assert ($null -ne $caught -and $caught.Message.StartsWith($Prefix)) ('Expected '+$Prefix+'; got '+$caught)
    $caught
}
$actionSpies=@'
function Action-Spy { throw 'UNEXPECTED_ACTION_DISPATCH' }
function Save-Snapshot { Action-Spy }
function Read-Snapshot { Action-Spy }
function Start-RestoreRun { Action-Spy }
function Show-RetryPreview { Action-Spy }
function Start-RetryRun { Action-Spy }
function New-ExplorerAdapter { Action-Spy }
function Get-ExplorerObservation { Action-Spy }
'@
try {
    Test 'L01 Known Folder anchor is absolute stable and outside Runs' {
        $expected=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'ResumeExplorer/resume-explorer.instance.lock'
        $before=Get-ResumeExplorerInstanceLockPath
        Push-Location $storage
        try { Assert ((Get-ResumeExplorerInstanceLockPath) -eq $expected -and $before -eq $expected) } finally { Pop-Location }
        # Only resolve the production path. Never open/create it in an offline suite.
        Assert ([IO.Path]::IsPathFullyQualified($before) -and [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($before)) -eq 'ResumeExplorer')
    }
    Test 'L01 L04 acquisition initializes parent and keeps the released anchor' {
        $f=New-Case; $path=Join-Path $f.Directory 'nested/instance.lock'
        Assert-Reacquire $path; Assert ([IO.File]::Exists($path)); Assert-Reacquire $path
        [IO.File]::WriteAllText($path,'stale anchor'); Assert-Reacquire $path
        Assert ([IO.File]::ReadAllText($path) -ceq 'stale anchor')
    }
    Test 'L02 L03 L06 independent PIDs reject Busy before holder release then reacquire' {
        $f=New-Case; $a=Start-Holder $f; $b=Start-Worker $f 'Try'
        Assert ($a.Process.Id -ne $b.Process.Id -and $a.Process.Id -ne $PID -and $b.Process.Id -ne $PID)
        $r=Finish-Child $b
        Assert ($r.Code -ne 0 -and $r.Text.Contains('InstanceLockBusy:') -and -not $r.Text.Contains('Acquired:')) $r.Text
        Assert (-not $a.Process.HasExited) 'Contender must fail while holder remains active'
        Release-Holder $f $a
        $r=Finish-Child (Start-Worker $f 'Try'); Assert ($r.Code -eq 0 -and $r.Text.Contains('Acquired:')) $r.Text
    }
    Test 'L05 CMD host different PWD and script copies share the same anchor' {
        $f=New-Case; $a=Start-Holder $f
        $dir=Join-Path $f.Directory "copy 中文 one's & space"; [void][IO.Directory]::CreateDirectory($dir)
        $cli=New-IsolatedTestCli $dir $actionSpies $f.Anchor
        Assert ((Get-FileHash -LiteralPath $cli).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'resume-explorer.ps1')).Hash)
        $batch=Join-Path $dir 'contender.cmd'
        [IO.File]::WriteAllText($batch,('@echo off'+"`r`n"+'"'+$engine+'" -NoProfile -NonInteractive -File "'+$cli+'" -Action Preview'+"`r`n"+'exit /b %ERRORLEVEL%'),[Text.UTF8Encoding]::new($false))
        # cmd reads batch files using its console code page. Set it in this child only.
        $text=[IO.File]::ReadAllText($batch).Replace('@echo off',"@echo off`r`nchcp 65001 >nul")
        [IO.File]::WriteAllText($batch,$text,[Text.UTF8Encoding]::new($false))
        $r=Finish-Child (Start-Child @() $storage $batch)
        Assert ($r.Code -ne 0 -and $r.Text.Contains('InstanceLockBusy:') -and -not $r.Text.Contains('UNEXPECTED_ACTION')) $r.Text
        Release-Holder $f $a
    }
    foreach ($action in @('Capture','Preview','Restore','PreviewRetry','Retry')) {
        Test "L07 L08 L13 L17 Busy $action rejects before any Action and leaves artifacts unchanged" {
            $f=New-Case; $a=Start-Holder $f
            $cli=New-IsolatedTestCli $f.Directory $actionSpies
            $snapshot=Join-Path $f.Directory 'snapshot.json'; $report=Join-Path $f.Directory 'report.json'
            $sidecar=$report+'.retry-preview.json'
            $files=@($snapshot,$report,$sidecar)
            foreach ($path in $files) { [IO.File]::WriteAllText($path,'sentinel') }
            $before=@($files | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash+'|'+[IO.File]::GetLastWriteTimeUtc($_).Ticks })
            $names=@([IO.Directory]::GetFileSystemEntries($f.Directory) | Sort-Object)
            $r=Finish-Child (Start-Child @('-File',$cli,'-Action',$action,'-Snapshot',$snapshot,'-ReportPath',$report))
            Assert ($r.Code -ne 0 -and $r.Text.Contains('InstanceLockBusy:') -and -not $r.Text.Contains('UNEXPECTED_ACTION')) $r.Text
            $after=@($files | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash+'|'+[IO.File]::GetLastWriteTimeUtc($_).Ticks })
            Assert (($before -join ',') -ceq ($after -join ','))
            Assert (($names -join ',') -ceq (([IO.Directory]::GetFileSystemEntries($f.Directory) | Sort-Object) -join ','))
            Assert (-not $a.Process.HasExited); Release-Holder $f $a
        }
    }
    Test 'L09 read-only anchor fails AccessDenied instead of Busy' {
        $f=New-Case; [IO.File]::WriteAllText($f.Anchor,'read-only')
        [IO.File]::SetAttributes($f.Anchor,[IO.FileAttributes]::ReadOnly)
        try { $null=Assert-LockError $f.Anchor 'InstanceLockAccessDenied:' }
        finally { [IO.File]::SetAttributes($f.Anchor,[IO.FileAttributes]::Normal) }
        Assert-Reacquire $f.Anchor
    }
    Test 'L09 explicit ACL denial on owned fixture fails closed and is reversible' {
        $f=New-Case; [IO.File]::WriteAllText($f.Anchor,'fixture ACL')
        $file=[IO.FileInfo]::new($f.Anchor)
        $acl=[IO.FileSystemAclExtensions]::GetAccessControl($file)
        $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User,
            [Security.AccessControl.FileSystemRights]::Write,[Security.AccessControl.AccessControlType]::Deny)
        try {
            $null=$acl.AddAccessRule($rule); [IO.FileSystemAclExtensions]::SetAccessControl($file,$acl)
            $null=Assert-LockError $f.Anchor 'InstanceLockAccessDenied:'
            $cli=New-IsolatedTestCli $f.Directory $actionSpies
            $r=Finish-Child (Start-Child @('-File',$cli,'-Action','Capture'))
            Assert ($r.Code -ne 0 -and $r.Text.Contains('InstanceLockAccessDenied:') -and -not $r.Text.Contains('UNEXPECTED_ACTION')) $r.Text
        } finally {
            # Remove the exact test-added rule; SetAccessControl on an unmodified old
            # FileSecurity object would not mark its ACL dirty or restore the access.
            $restore=[IO.FileSystemAclExtensions]::GetAccessControl($file)
            $restore.RemoveAccessRuleSpecific($rule); [IO.FileSystemAclExtensions]::SetAccessControl($file,$restore)
        }
        Assert-Reacquire $f.Anchor
    }
    Test 'L10 invalid path parent and non-sharing IO errors fail closed' {
        foreach ($path in @('', 'relative.lock')) { $null=Assert-LockError $path 'InstanceLockPathError:' }
        $f=New-Case; [IO.File]::WriteAllText($f.Anchor,'parent file')
        $null=Assert-LockError (Join-Path $f.Anchor 'child.lock') 'InstanceLockPathError:'
        $null=Assert-LockError ($f.Anchor+':bad:stream') 'InstanceLockOpenFailed:'
        $directory=Join-Path $f.Directory 'directory'; [void][IO.Directory]::CreateDirectory($directory)
        $null=Assert-LockError $directory 'InstanceLockAccessDenied:'
    }
    Test 'L10 CLI acquisition errors are nonzero and never dispatch Actions' {
        $f=New-Case; $cli=New-IsolatedTestCli $f.Directory $actionSpies (Join-Path $f.Directory 'bad/child.lock')
        [IO.File]::WriteAllText((Join-Path $f.Directory 'bad'),'parent file')
        $r=Finish-Child (Start-Child @('-File',$cli,'-Action','Capture'))
        Assert ($r.Code -ne 0 -and $r.Text.Contains('InstanceLockPathError:') -and -not $r.Text.Contains('UNEXPECTED_ACTION')) $r.Text
    }
    Test 'L11 all five successful Actions hold global handle and finally release' {
        foreach ($action in @('Capture','Preview','Restore','PreviewRetry','Retry')) {
            $f=New-Case
            $overrides=@'
function Assert-Held {
    $caught=$null
    try { $h=Enter-ResumeExplorerInstanceLock (Get-ResumeExplorerInstanceLockPath); $h.Dispose() } catch { $caught=$_.Exception }
    if ($null -eq $caught -or -not $caught.Message.StartsWith('InstanceLockBusy:')) { throw 'GlobalNotHeldDuringAction' }
    Write-Host 'ACTION_HELD'
}
function Save-Snapshot { Assert-Held }
function Read-Snapshot { Assert-Held; [pscustomobject]@{Windows=@()} }
function Start-RestoreRun { Assert-Held }
function Show-RetryPreview { Assert-Held }
function Start-RetryRun { Assert-Held }
'@
            $cli=New-IsolatedTestCli $f.Directory $overrides
            $r=Finish-Child (Start-Child @('-File',$cli,'-Action',$action))
            Assert ($r.Code -eq 0 -and $r.Text.Contains('ACTION_HELD')) $r.Text
            Assert-Reacquire $f.Anchor
        }
    }
    Test 'L11 Action IOException keeps its identity and is not reclassified as Busy' {
        $f=New-Case
        $exceptionState=@{}
        $overrides=@'
if ($null -eq $exceptionState) { $exceptionState=@{} }
$exceptionState.Exception=[IO.IOException]::new('OriginalActionIOException')
function Save-Snapshot { throw $exceptionState.Exception }
'@
        $cli=New-IsolatedTestCli $f.Directory $overrides
        # Calling script in-process lets us verify exact Exception object identity and finally.
        $caught=$null; try { & $cli -Action Capture } catch { $caught=$_.Exception }
        Assert ([object]::ReferenceEquals($caught,$exceptionState.Exception))
        Assert ($caught.Message -ceq 'OriginalActionIOException'); Assert-Reacquire $f.Anchor
        $r=Finish-Child (Start-Child @('-File',$cli,'-Action','Capture'))
        Assert ($r.Code -ne 0 -and $r.Text.Contains('OriginalActionIOException') -and -not $r.Text.Contains('InstanceLockBusy:')) $r.Text
        Assert-Reacquire $f.Anchor
    }
    Test 'L12 owned holder termination releases OS handle without deleting anchor' {
        $f=New-Case; $a=Start-Holder $f
        $a.Process.Kill(); $null=Finish-Child $a
        Assert ([IO.File]::Exists($f.Anchor)); Assert-Reacquire $f.Anchor
        $r=Finish-Child (Start-Worker $f 'Try'); Assert ($r.Code -eq 0) $r.Text
    }
    Test 'L14 real Retry checkpoint summary and family finally finish before global release' {
        $f=New-Case
        $fp=[pscustomobject]@{Hwnd=10L;RootHwnd=10L;PID=42;ProcessStartedAtUtc='2026-11-01T00:00:00Z';SessionId=1}
        $sourcePath=Join-Path $f.Directory 'source.json'
        $run=New-Run @((New-RestoreItem 1 1 $f.Directory)) 'snapshot-hash' 'fixture-snapshot' $null
        $run.RootRunId=$run.RunId; $run.RootReportPath=$sourcePath; $run.State='Completed'
        [IO.File]::WriteAllText($sourcePath,(ConvertTo-Json -InputObject $run -Depth 32))
        $preview=@{RunId=$run.RunId;ReportHash=(Get-FileHash -LiteralPath $sourcePath).Hash;Targets=@($fp)}
        [IO.File]::WriteAllText(($sourcePath+'.retry-preview.json'),(ConvertTo-Json -InputObject $preview -Depth 8))
        $overrides=@'
function Probe-Held([string]$Path) {
    $caught=$null
    try { $h=Enter-ResumeExplorerInstanceLock $Path; $h.Dispose() } catch { $caught=$_.Exception }
    if ($null -eq $caught -or -not $caught.Message.StartsWith('InstanceLockBusy:')) { throw 'ExpectedHeldLock' }
}
function New-ExplorerAdapter {
    @{Fingerprint={param($hwnd) [pscustomobject]@{Hwnd=10L;RootHwnd=10L;PID=42;ProcessStartedAtUtc='2026-11-01T00:00:00Z';SessionId=1}}}
}
function Invoke-RestoreGroups($Run) { $Run.Items[0].Status='Verified' }
function Write-RunSummary($Run,$Path) {
    Probe-Held (Get-ResumeExplorerInstanceLockPath)
    Probe-Held ((Join-Path $PSScriptRoot 'source.json')+'.retry.lock')
    $checkpoint=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($checkpoint.State -ne 'Completed' -or $checkpoint.Items[0].Status -ne 'Verified') { throw 'FinalCheckpointMissing' }
    Write-Host 'SUMMARY_BOTH_HELD'
}
$script:actualRetry=${function:Start-RetryRun}
function Start-RetryRun([string]$ReportPath,[int]$GroupIndex,[long]$TargetHwnd,[int[]]$ItemIndexes,[switch]$IncludeUncertain,$Config) {
    try { & $script:actualRetry @PSBoundParameters }
    finally {
        $h=Enter-ResumeExplorerInstanceLock ($ReportPath+'.retry.lock'); $h.Dispose()
        Probe-Held (Get-ResumeExplorerInstanceLockPath)
        Write-Host 'FAMILY_RELEASED_GLOBAL_HELD'
    }
}
'@
        $cli=New-IsolatedTestCli $f.Directory $overrides
        $r=Finish-Child (Start-Child @('-File',$cli,'-Action','Retry','-ReportPath',$sourcePath,'-GroupIndex','1','-TargetHwnd','10','-ItemIndexes','1'))
        Assert ($r.Code -eq 0 -and $r.Text.Contains('SUMMARY_BOTH_HELD') -and $r.Text.Contains('FAMILY_RELEASED_GLOBAL_HELD')) $r.Text
        Assert-Reacquire $f.Anchor; Assert-Reacquire ($sourcePath+'.retry.lock')
    }
    Test 'L16 repeated simultaneous contenders never have two holders' {
        for ($round=0;$round -lt 3;$round++) {
            $f=New-Case; $g=New-Case
            $f.Anchor=Join-Path $f.Directory 'concurrent-parent/instance.lock'
            $g.Anchor=$f.Anchor; $g.Gate=$f.Gate; $g.Release=$f.Release
            # Synchronize startup separately; neither process may acquire before the
            # shared gate. The race begins only after both PIDs report readiness.
            $a=Start-Worker $f 'Race'
            Wait-Until { [IO.File]::Exists($f.Ready) -or $a.Process.HasExited } 'first contender ready'
            if ($a.Process.HasExited) { $r=Finish-Child $a; throw ('First contender exited before gate: '+$r.Text) }
            $b=Start-Worker $g 'Race'
            Wait-Until { [IO.File]::Exists($g.Ready) -or $b.Process.HasExited } 'second contender ready'
            if ($b.Process.HasExited) { $r=Finish-Child $b; throw ('Second contender exited before gate: '+$r.Text) }
            Assert ([IO.File]::ReadAllText($f.Ready) -eq [string]$a.Process.Id -and [IO.File]::ReadAllText($g.Ready) -eq [string]$b.Process.Id)
            [IO.File]::WriteAllText($f.Gate,'start')
            Wait-Until { [IO.File]::Exists($f.Acquired) -or [IO.File]::Exists($g.Acquired) } 'winner acquired'
            Wait-Until { $a.Process.HasExited -or $b.Process.HasExited } 'loser exits while winner holds'
            Assert ([IO.File]::Exists($f.Acquired) -xor [IO.File]::Exists($g.Acquired))
            $loser=$a; $winner=$b; if ($b.Process.HasExited) { $loser=$b; $winner=$a }
            $r=Finish-Child $loser
            Assert ($r.Code -ne 0 -and $r.Text.Contains('InstanceLockBusy:') -and -not $winner.Process.HasExited) $r.Text
            [IO.File]::WriteAllText($f.Release,'release'); $r=Finish-Child $winner; Assert ($r.Code -eq 0) $r.Text
            Assert-Reacquire $f.Anchor
        }
    }
    Test 'L10 newly initialized parent keeps its exclusive anchor until release' {
        $f=New-Case; $f.Anchor=Join-Path $f.Directory 'new-parent/instance.lock'
        $a=Start-Holder $f; $null=Assert-LockError $f.Anchor 'InstanceLockBusy:'
        Release-Holder $f $a; Assert-Reacquire $f.Anchor
    }
    Test 'L18 CLI exit unwinds finally and reacquires the retained anchor' {
        $f=New-Case; $cli=New-IsolatedTestCli $f.Directory 'function Save-Snapshot { exit 7 }'
        $r=Finish-Child (Start-Child @('-File',$cli,'-Action','Capture'))
        Assert ($r.Code -eq 7) $r.Text; Assert-Reacquire $f.Anchor
    }
    Write-Host "Instance lock tests passed: $passed"
} finally {
    # Only process objects started by this suite are eligible for bounded cleanup.
    foreach ($child in $children) {
        try { if (-not $child.Process.HasExited) { $child.Process.Kill($true); $null=$child.Process.WaitForExit(5000) } }
        finally { $child.Process.Dispose() }
    }
    $absolute=[IO.Path]::GetFullPath($storage)
    if ([IO.Path]::GetDirectoryName($absolute) -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -and
        [IO.Path]::GetFileName($absolute) -match '^ResumeExplorer-LockTests-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $absolute -Recurse -Force
    } else { throw 'UnsafeLockTestCleanup' }
}
