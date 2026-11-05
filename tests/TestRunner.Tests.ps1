# T01-T08. Synthetic child scripts only; never dispatch the real manifest recursively.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestRunner.Core.ps1')
$engine=Get-OfflineTestEngine
$storage=Join-Path ([IO.Path]::GetTempPath()) ('ResumeExplorer-RunnerTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($storage)
$passed=0
function Assert($Condition,$Message='Runner assertion failed') { if (-not $Condition) { throw $Message } }
function Test($Name,$Body) { & $Body; $script:passed++; Write-Host "PASS $Name" }
function Reject($Body) { $caught=$false; try { & $Body } catch { $caught=$true }; Assert $caught }
function Fixture($Text,[int]$Expected=1) {
    $name=[guid]::NewGuid().ToString('N')+'.ps1'
    [IO.File]::WriteAllText((Join-Path $storage $name),$Text,[Text.UTF8Encoding]::new($false))
    @{ File=$name; Expected=$Expected }
}
function Collect($Manifest,[switch]$FailFast) {
    @(Invoke-OfflineTestCollector -Manifest $Manifest -TestsRoot $storage -Engine $engine -FailFast:$FailFast)
}
function EntryFixture([string]$Mode='Passed',[switch]$DotSource) {
    $folder=Join-Path $storage ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($folder)
    foreach ($name in @('Invoke-Tests.ps1','TestRunner.Core.ps1')) {
        $target=$name; if ($name -eq 'TestRunner.Core.ps1') { $target='ActualCore.ps1' }
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $folder $target)
    }
    $body="Write-Host 'PASS synthetic'"
    if ($Mode -eq 'Failed') { $body+="`nexit 17" }
    [IO.File]::WriteAllText((Join-Path $folder 'Synthetic.ps1'),$body)
    $dependency=@'
. (Join-Path $PSScriptRoot 'ActualCore.ps1')
function Get-OfflineTestManifest { @{File='Synthetic.ps1';Expected=1} }
'@
    if ($Mode -eq 'ManifestError') { $dependency+="`nfunction Get-OfflineTestManifest { @() }" }
    if ($Mode -eq 'WriteError') { $dependency+="`nfunction Save-OfflineTestEvidence { throw 'SyntheticEvidenceWriteFailure' }" }
    if ($Mode -eq 'ReportError') {
        $dependency+=@'

$script:actualSave=${function:Save-OfflineTestEvidence}
function Save-OfflineTestEvidence($Run,$Directory) {
    [void][IO.Directory]::CreateDirectory((Join-Path $Directory 'result.json'))
    & $script:actualSave $Run $Directory
}
'@
    }
    if ($Mode -eq 'LogError') {
        $dependency+=@'

$script:actualSave=${function:Save-OfflineTestEvidence}
function Save-OfflineTestEvidence($Run,$Directory) {
    [void][IO.Directory]::CreateDirectory((Join-Path $Directory 'Synthetic.ps1.log'))
    & $script:actualSave $Run $Directory
}
'@
    }
    if ($Mode -eq 'EnvironmentError') { $dependency+="`nfunction Get-OfflineTestEngine { throw 'SyntheticEnvironmentFailure' }" }
    [IO.File]::WriteAllText((Join-Path $folder 'TestRunner.Core.ps1'),$dependency)
    $temp=Join-Path $folder 'temp'; [void][IO.Directory]::CreateDirectory($temp)
    $homeDir=Join-Path $folder 'home'; [void][IO.Directory]::CreateDirectory($homeDir)
    $sentinel=Join-Path $temp 'ExplorerTabs-snapshot.json'; [IO.File]::WriteAllText($sentinel,'sentinel')
    $homeSentinel=Join-Path $homeDir 'user-sentinel'; [IO.File]::WriteAllText($homeSentinel,'unchanged')
    $stale=Join-Path $temp 'result.json'; [IO.File]::WriteAllText($stale,'{"OverallStatus":"Passed","RunId":"stale"}')
    $entry=Join-Path $folder 'Invoke-Tests.ps1'
    if ($DotSource) {
        $quoted=$entry.Replace("'","''")
        $entry=Join-Path $folder 'Import.ps1'
        [IO.File]::WriteAllText($entry,". '$quoted'`nif (-not (Get-Command Invoke-OfflineTests)) { exit 9 }")
    }
    $savedTemp=$env:TEMP; $savedTmp=$env:TMP; $savedHome=$env:HOME; $savedLocal=$env:LOCALAPPDATA; $savedProfile=$env:USERPROFILE
    try {
        $env:TEMP=$temp; $env:TMP=$temp; $env:HOME=$homeDir; $env:USERPROFILE=$homeDir; $env:LOCALAPPDATA=$homeDir
        $result=Invoke-OfflineTestProcess $engine $entry
    } finally { $env:TEMP=$savedTemp; $env:TMP=$savedTmp; $env:HOME=$savedHome; $env:USERPROFILE=$savedProfile; $env:LOCALAPPDATA=$savedLocal }
    Assert ([IO.File]::ReadAllText($sentinel) -ceq 'sentinel')
    Assert ([IO.File]::ReadAllText($homeSentinel) -ceq 'unchanged')
    # PS7 itself creates Microsoft/PowerShell startup telemetry in LOCALAPPDATA,
    # even with -NoProfile. Assert product data and explicit sentinels instead.
    Assert (-not [IO.Directory]::Exists((Join-Path $homeDir 'ResumeExplorer'))) 'Runner wrote product user data'
    Assert ([IO.File]::ReadAllText($stale) -ceq '{"OverallStatus":"Passed","RunId":"stale"}')
    $reports=@(Get-ChildItem -LiteralPath $temp -Filter result.json -Recurse -File | Where-Object FullName -ne $stale)
    @{ Result=$result; Reports=$reports; Temp=$temp }
}
try {
    Test 'T01 exact positive count and zero raw exit pass' {
        $r=Collect @((Fixture "Write-Host 'PASS one'")); Assert ($r.Count -eq 1 -and $r[0].Status -eq 'Passed' -and $r[0].RawExitCode -eq 0)
    }
    Test 'T01 full PASS followed by nonzero exit or throw fails and preserves raw exit' {
        foreach ($end in @('exit 17',"throw '真實錯誤'")) {
            $r=Collect @((Fixture ("Write-Host 'PASS one'`n"+$end)))
            Assert ($r[0].Status -eq 'Failed' -and $r[0].ObservedPassed -eq 1 -and $r[0].RawExitCode -ne 0)
            if ($end -eq 'exit 17') { Assert ($r[0].RawExitCode -eq 17) }
            else { Assert (($r[0].Output -join "`n").Contains('真實錯誤')) }
        }
    }
    Test 'T02 zero insufficient excessive duplicate and early PASS outputs cannot pass' {
        foreach ($text in @('',"Write-Host 'PASS one'", "Write-Host 'PASS one'`nWrite-Host 'PASS two'`nWrite-Host 'PASS three'",
            "Write-Host 'PASS same'`nWrite-Host 'PASS same'", "Write-Host 'PASS one'`nexit 0`nWrite-Host 'PASS two'")) {
            $r=Collect @((Fixture $text 2)); Assert ($r[0].Status -eq 'Failed' -and $r[0].RawExitCode -eq 0)
        }
    }
    Test 'T02 missing script launch error and invalid manifests fail closed' {
        $r=Collect @(@{File='missing.ps1';Expected=1}); Assert ($r[0].Status -eq 'Error' -and $null -eq $r[0].RawExitCode)
        $f=Fixture ''; $r=@(Invoke-OfflineTestCollector @($f) $storage $engine -Launch { throw 'LaunchFailure' })
        Assert ($r[0].Status -eq 'Error' -and $null -eq $r[0].RawExitCode -and $r[0].Reason -eq 'LaunchFailure')
        Reject { Collect @() }
        foreach ($expected in @(0,-1,'1')) { Reject { Collect @(@{File='x.ps1';Expected=$expected}) } }
        Reject { Collect @(@{File='../x.ps1';Expected=1}) }; Reject { Collect @($f,$f) }
    }
    Test 'T03 fail fast leaves subsequent suite unlaunched and NotRun' {
        $sentinel=Join-Path $storage 'launched'; $quoted=$sentinel.Replace("'","''")
        $r=Collect @((Fixture 'exit 3'),(Fixture "[IO.File]::WriteAllText('$quoted','bad')")) -FailFast
        Assert ($r.Count -eq 2 -and $r[1].Status -eq 'NotRun' -and $null -eq $r[1].RawExitCode -and -not [IO.File]::Exists($sentinel))
        $dir=Join-Path $storage 'failfast-evidence'; [void][IO.Directory]::CreateDirectory($dir)
        Save-OfflineTestEvidence ([ordered]@{Suites=$r;OverallStatus='Failed'}) $dir
        $report=Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json
        Assert ($report.Suites[1].Status -eq 'NotRun' -and $null -eq $report.Suites[1].RawExitCode)
    }
    Test 'T03 collect all preserves multiple independent failures' {
        $r=Collect @((Fixture 'exit 3'),(Fixture 'exit 4'))
        Assert ($r.Count -eq 2 -and $r[0].RawExitCode -eq 3 -and $r[1].RawExitCode -eq 4)
    }
    Test 'T04 full Unicode error and stack survive UTF8 evidence serialization' {
        $r=Collect @((Fixture "Write-Host '資料 stdout'`nfunction Fail { throw '真正錯誤' }; Fail"))
        $dir=Join-Path $storage 'evidence'; [void][IO.Directory]::CreateDirectory($dir)
        $run=[ordered]@{ Version=1; OverallStatus='Failed'; Suites=$r; E2E=@{Status='NotRun';Reason='OfflineOnly'} }
        Save-OfflineTestEvidence $run $dir
        $log=[IO.File]::ReadAllText($r[0].LogPath)
        Assert ($log.Contains('資料 stdout') -and $log.Contains('真正錯誤') -and $log.Contains('function Fail'))
        $report=Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json
        Assert ($report.Suites[0].RawExitCode -ne 0 -and $report.OverallStatus -eq 'Failed' -and $report.E2E.Status -eq 'NotRun')
        Reject { Save-OfflineTestEvidence $run $dir }
    }
    Test 'T05 literal special script and engine paths work from another PWD' {
        $dir=Join-Path $storage "space 中文 one's & path"; [void][IO.Directory]::CreateDirectory($dir)
        $path=Join-Path $dir "script one's 中文.ps1"; [IO.File]::WriteAllText($path,"Write-Host 'PASS literal'")
        # Engine location is system-owned; use a directory junction inside our owned fixture.
        $link=Join-Path $dir 'engine 中文 space'
        $null=New-Item -ItemType Junction -Path $link -Target ([IO.Path]::GetDirectoryName($engine))
        try {
            Push-Location $dir
            try { $r=Invoke-OfflineTestProcess (Join-Path $link 'pwsh.exe') $path } finally { Pop-Location }
            Assert ($r.RawExitCode -eq 0 -and $r.Lines[0] -ceq 'PASS literal')
        } finally { Remove-Item -LiteralPath $link -Force }
    }
    Test 'T06 ASCII and UTF8 restore caller encoding after success and launch error' {
        $saved=[Console]::OutputEncoding
        try {
            foreach ($encoding in @([Text.Encoding]::ASCII,[Text.UTF8Encoding]::new($false))) {
                [Console]::OutputEncoding=$encoding
                $f=Fixture "Write-Host 'PASS 中文資料'"
                $r=Invoke-OfflineTestProcess $engine (Join-Path $storage $f.File)
                Assert ($r.Lines[0] -ceq 'PASS 中文資料' -and [Console]::OutputEncoding.CodePage -eq $encoding.CodePage)
                Reject { Invoke-OfflineTestProcess (Join-Path $storage 'no-engine.exe') 'x' }
                Assert ([Console]::OutputEncoding.CodePage -eq $encoding.CodePage)
            }
        } finally { [Console]::OutputEncoding=$saved }
    }
    Test 'T06 interleaved large stdout stderr completes without truncated PASS count' {
        $f=Fixture 'for ($i=0;$i -lt 3000;$i++) { [Console]::Out.WriteLine("out-$i"); [Console]::Error.WriteLine("err-$i") }; Write-Host "PASS large"'
        $r=Collect @($f); Assert ($r[0].Status -eq 'Passed' -and $r[0].Output.Count -eq 6001)
        Assert ($r[0].Output -contains 'err-2999' -and $r[0].Output -contains 'out-2999')
    }
    Test 'T07 unchanged entry exit and committed report agree on success and failure' {
        foreach ($mode in @('Passed','Failed')) {
            $f=EntryFixture $mode; $expected=0; if ($mode -eq 'Failed') { $expected=1 }
            Assert ($f.Result.RawExitCode -eq $expected -and $f.Reports.Count -eq 1)
            $report=Get-Content -LiteralPath $f.Reports[0].FullName -Raw | ConvertFrom-Json
            Assert ($report.OverallStatus -eq $mode -and $report.EnginePath -eq $engine -and $report.Version -eq 1)
            Assert ($report.E2E.Status -eq 'NotRun' -and $report.E2E.Reason -eq 'OfflineOnly')
            Assert ($report.Suites.Count -eq 1 -and [IO.File]::Exists($report.Suites[0].LogPath))
        }
    }
    Test 'T04 T07 entry environment manifest log and report errors cannot return zero' {
        foreach ($mode in @('EnvironmentError','ManifestError','LogError','ReportError','WriteError')) {
            $f=EntryFixture $mode
            Assert ($f.Result.RawExitCode -eq 2)
            if ($mode -eq 'ManifestError') {
                Assert ($f.Reports.Count -eq 1)
                $report=Get-Content -LiteralPath $f.Reports[0].FullName -Raw | ConvertFrom-Json
                Assert ($report.OverallStatus -eq 'Error' -and $report.Reason.Contains('InvalidOfflineManifest'))
            } else { Assert ($f.Reports.Count -eq 0) }
            if ($mode -eq 'ReportError') { Assert (@(Get-ChildItem -LiteralPath $f.Temp -Filter '*.log' -Recurse -File).Count -eq 1) }
            Assert (($f.Result.Lines -join "`n").Contains('Offline runner error:'))
        }
    }
    Test 'T07 dot source entry defines functions without logs or execution' {
        $f=EntryFixture -DotSource
        Assert ($f.Result.RawExitCode -eq 0 -and $f.Reports.Count -eq 0)
        Assert (@(Get-ChildItem -LiteralPath $f.Temp -Directory).Count -eq 0)
    }
    Test 'T08 manifest preserves all original suites counts and order' {
        $manifest=@(Get-OfflineTestManifest)
        Assert (($manifest[0..4].File -join ',') -eq 'Issue2.Tests.ps1,RestoreSummary.Tests.ps1,ExplorerSmoke.Tests.ps1,ExplorerSmoke.OneClick.Tests.ps1,ExplorerSmoke.Recovery.Tests.ps1')
        Assert (($manifest[0..4].Expected -join ',') -eq '39,17,23,49,13')
        Assert ($manifest.Count -eq 7 -and $manifest[5].File -eq 'Snapshot.Tests.ps1' -and $manifest[6].File -eq 'TestRunner.Tests.ps1')
    }
    Test 'T08 smoke wrapper retains rows and failure Reason with fail fast delegation' {
        & {
            . (Join-Path $PSScriptRoot 'Integration/ExplorerSmoke.OneClick.Core.ps1')
            $script:baselineFailed=$false
            function Invoke-OfflineTestRun([switch]$FailFast) {
                Assert $FailFast
                $manifest=@((Fixture "Write-Host 'PASS first'"),(Fixture "Write-Host 'PASS second'"))
                if ($script:baselineFailed) { [IO.File]::WriteAllText((Join-Path $storage $manifest[0].File),"throw 'Original baseline error'") }
                $rows=Collect $manifest -FailFast
                $code=0; if ($script:baselineFailed) { $code=1 }
                @{ ExitCode=$code; Run=@{Suites=$rows}; EvidencePath=$storage }
            }
            $rows=@(Invoke-SmokeOfflineBaseline)
            Assert ($rows.Count -eq 2 -and $rows[0].Passed -eq 1 -and $rows[1].ExitCode -eq 0)
            Assert (($rows[0].PSObject.Properties.Name -join ',') -eq 'Suite,Passed,ExitCode')
            $script:baselineFailed=$true; $message=''
            try { Invoke-SmokeOfflineBaseline } catch { $message=$_.Exception.Message }
            Assert ($message -match '^OfflineBaselineFailed:[a-f0-9]{32}\.ps1$')
        }
    }
    Test 'T07 runner core import is inert and engine validation fails closed' {
        & {
            function Get-Process { throw 'ImportProcessSpy' }
            function New-Item { throw 'ImportWriteSpy' }
            . (Join-Path $PSScriptRoot 'TestRunner.Core.ps1')
            Reject { Get-OfflineTestEngine }
        }
        # Public offline entry has no GUI dispatch switch or dependency.
        $entry=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-Tests.ps1') -Raw
        Assert ($entry -notmatch 'ExplorerSmoke|Restore|Retry|Start-Process|ComObject|UIAutomation')
    }
    Write-Host "Runner tests passed: $passed"
} finally {
    $absolute=[IO.Path]::GetFullPath($storage)
    if ([IO.Path]::GetDirectoryName($absolute) -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -and
        [IO.Path]::GetFileName($absolute) -match '^ResumeExplorer-RunnerTests-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $absolute -Recurse -Force
    } else { throw 'UnsafeRunnerTestCleanup' }
}
