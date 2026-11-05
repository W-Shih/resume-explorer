# S01-S10: real writer/parser/CLI, with platform boundaries replaced in this process.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$storage=Join-Path ([IO.Path]::GetTempPath()) ('ResumeExplorer-SnapshotTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($storage)
$passed=0
function Assert($Condition,$Message='Snapshot assertion failed') { if (-not $Condition) { throw $Message } }
function Test($Name,$Body) { & $Body; $script:passed++; Write-Host "PASS $Name" }
function Reject($Body) { $caught=$false; try { & $Body } catch { $caught=$true }; Assert $caught 'Expected rejection' }
try {
    # Verify command-resolution spies before import; never fall through to platform commands.
    $script:platformCalls=0
    function New-Object { $script:platformCalls++; throw 'PlatformSpy' }
    function Add-Type { $script:platformCalls++; throw 'PlatformSpy' }
    function Start-Process { $script:platformCalls++; throw 'PlatformSpy' }
    function Set-Content { $script:platformCalls++; throw 'WriteSpy' }
    Test 'S01 platform spies intercept and core import has no dispatch' {
        foreach ($probe in @({ New-Object -ComObject Shell.Application },{ Add-Type 'x' },{ Start-Process explorer },{ Set-Content x y })) { Reject $probe }
        Assert ($script:platformCalls -eq 4)
        . (Join-Path $root 'resume-explorer.core.ps1')
        Assert ($script:platformCalls -eq 4)
        Assert (-not ('ResumeExplorerNative' -as [type]))
    }
    Remove-Item Function:New-Object,Function:Add-Type,Function:Start-Process,Function:Set-Content
    . (Join-Path $root 'resume-explorer.core.ps1')
    $script:obs=[pscustomobject]@{ IdentitySetReliable=$true; Views=@() }
    function Get-ExplorerObservation { $script:obs }
    function New-ExplorerAdapter { $script:adapterCalls++; throw 'AdapterSpy' }
    function Initialize-RunPath { $script:reportCalls++; throw 'ReportSpy' }
    $script:adapterCalls=0; $script:reportCalls=0
    $config=@{ DetectionTimeoutSeconds=15; PollIntervalMs=200; StableDurationMs=600; BaselineTimeoutSeconds=3
        NavigationTimeoutSeconds=10; TransientErrorBackoffMs=@(200,400,800) }
    $snapshot=Join-Path $storage 'snapshot.json'
    $report=Join-Path $storage 'report.json'
    function View($Group,$Path,$Readable=$true) { [pscustomobject]@{ RawHwnd=$Group; Path=$Path; PathReadable=$Readable } }
    function Roundtrip($Views) {
        $script:obs=[pscustomobject]@{ IdentitySetReliable=$true; Views=@($Views) }
        Save-Snapshot $snapshot
        Read-Snapshot $snapshot
    }
    $a=Join-Path $storage "資料 one's & space"
    $b=Join-Path $storage 'literal $(Write-Output evaluated)'
    [void][IO.Directory]::CreateDirectory($a); [void][IO.Directory]::CreateDirectory($b)
    Test 'S02 zero views saves and reads non-null empty Windows array' {
        $data=Roundtrip @(); Assert ($null -ne $data.Windows -and $data.Windows -is [array] -and $data.Windows.Count -eq 0)
        Assert ((Get-Content -LiteralPath $snapshot -Raw) -match '"Windows":\s*\[\s*\]')
    }
    Test 'S03 singleton writer and reader preserve both arrays' {
        $data=Roundtrip @(View 10 $a)
        Assert ($data.Windows -is [array] -and $data.Windows.Count -eq 1)
        Assert ($data.Windows[0].Paths -is [array] -and $data.Windows[0].Paths.Count -eq 1)
        $json=Get-Content -LiteralPath $snapshot -Raw
        Assert ($json -match '"Windows":\s*\[' -and $json -match '"Paths":\s*\[')
    }
    foreach ($groups in @(2,3)) {
        Test "S04 $groups groups preserve duplicate path multisets" {
            $views=@(); for ($i=1;$i -le $groups;$i++) { $views+=View $i $a; $views+=View $i $a; $views+=View $i $b }
            $data=Roundtrip $views; Assert ($data.Windows.Count -eq $groups)
            foreach ($group in $data.Windows) {
                Assert ($group.Paths.Count -eq 3)
                Assert (@($group.Paths | Where-Object { $_ -ceq $a }).Count -eq 2)
                Assert (@($group.Paths | Where-Object { $_ -ceq $b }).Count -eq 1)
            }
        }
    }
    Test 'S05 UTF8 special characters and expression text remain literal' {
        $data=Roundtrip @((View 1 $a),(View 1 $b))
        Assert ($data.Windows[0].Paths[0] -ceq $a); Assert ($data.Windows[0].Paths[1] -ceq $b)
        $text=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($snapshot))
        Assert ($text.Contains('資料') -and $text.Contains('$(Write-Output evaluated)'))
    }
    Test 'S06 capture filters unreadable missing and file paths' {
        $file=Join-Path $storage 'file'; [IO.File]::WriteAllText($file,'x')
        $data=Roundtrip @((View 1 $a),(View 1 $b $false),(View 2 $file),(View 2 (Join-Path $storage 'missing')))
        Assert ($data.Windows.Count -eq 1 -and $data.Windows[0].Paths.Count -eq 1 -and $data.Windows[0].Paths[0] -ceq $a)
    }
    Test 'S06 unreliable capture cannot overwrite existing or create new snapshot' {
        $script:obs.IdentitySetReliable=$false
        [IO.File]::WriteAllText($snapshot,'sentinel'); $hash=(Get-FileHash -LiteralPath $snapshot).Hash
        Reject { Save-Snapshot $snapshot }; Assert ((Get-FileHash -LiteralPath $snapshot).Hash -eq $hash)
        $absent=Join-Path $storage 'absent.json'; Reject { Save-Snapshot $absent }; Assert (-not [IO.File]::Exists($absent))
    }
    foreach ($json in @('{"Version":1,"Windows":[]}','{"Version":1,"Windows":[{"Paths":[]}]}')) {
        Test "S07 legal empty collections $json" {
            [IO.File]::WriteAllText($snapshot,$json); $data=Read-Snapshot $snapshot
            Assert ($null -ne $data.Windows -and $data.Windows -is [array])
            if ($data.Windows.Count) { Assert ($null -ne $data.Windows[0].Paths -and $data.Windows[0].Paths.Count -eq 0) }
        }
    }
    $invalid=@('{','{"Windows":[]}','{"Version":2,"Windows":[]}','{"Version":1}',
        '{"Version":1,"Windows":null}','{"Version":1,"Windows":[{}]}','{"Version":1,"Windows":[{"Paths":null}]}')
    Test 'S08 parser rejects malformed missing unsupported and null fields' {
        foreach ($json in $invalid) { [IO.File]::WriteAllText($snapshot,$json); Reject { Read-Snapshot $snapshot } }
    }
    Test 'S08 missing file and exclusive read lock reject deterministically' {
        Reject { Read-Snapshot (Join-Path $storage 'missing.json') }
        [IO.File]::WriteAllText($snapshot,'{"Version":1,"Windows":[]}')
        $lock=[IO.File]::Open($snapshot,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try { Reject { Read-Snapshot $snapshot } } finally { $lock.Dispose() }
    }
    Test 'S09 restore spies intercept independently before boundary tests' {
        Reject { New-ExplorerAdapter }; Reject { Initialize-RunPath $null $report }
        Assert ($script:adapterCalls -eq 1 -and $script:reportCalls -eq 1)
        $script:adapterCalls=0; $script:reportCalls=0
    }
    Test 'S09 real restore rejects invalid inputs before adapter or report initialization' {
        foreach ($json in $invalid) {
            [IO.File]::WriteAllText($snapshot,$json)
            Reject { Start-RestoreRun $snapshot $report $config }
        }
        Reject { Start-RestoreRun (Join-Path $storage 'missing.json') $report $config }
        Assert ($script:adapterCalls -eq 0 -and $script:reportCalls -eq 0 -and -not [IO.File]::Exists($report))
    }
    $engine=(Get-Process -Id $PID).Path
    # Preserve the public entry unchanged, isolate the newly added user-wide lock.
    . (Join-Path $PSScriptRoot 'Fixtures/IsolatedCli.ps1')
    $cli=New-IsolatedTestCli $storage
    $childTemp=Join-Path $storage 'child-temp'; [void][IO.Directory]::CreateDirectory($childTemp)
    $sentinel=Join-Path $childTemp 'ExplorerTabs-snapshot.json'; [IO.File]::WriteAllText($sentinel,'default sentinel')
    function Preview($Path) {
        $savedTemp=$env:TEMP; $savedTmp=$env:TMP; $encoding=[Console]::OutputEncoding
        try {
            $env:TEMP=$childTemp; $env:TMP=$childTemp; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
            $output=@(& $engine -NoProfile -NonInteractive -File $cli -Action Preview -Snapshot $Path 2>&1)
            $code=$LASTEXITCODE
            @{ Code=$code; Text=($output -join "`n") }
        } finally { $env:TEMP=$savedTemp; $env:TMP=$savedTmp; [Console]::OutputEncoding=$encoding }
    }
    Test 'S10 public Preview succeeds and preserves exact input bytes' {
        $null=Roundtrip @((View 1 $a),(View 1 $b)); $hash=(Get-FileHash -LiteralPath $snapshot).Hash
        $result=Preview $snapshot; Assert ($result.Code -eq 0 -and $result.Text.Contains($a) -and $result.Text.Contains($b))
        Assert ((Get-FileHash -LiteralPath $snapshot).Hash -eq $hash)
    }
    Test 'S10 malformed Preview exits nonzero with diagnostic and unchanged bytes' {
        [IO.File]::WriteAllText($snapshot,'{'); $hash=(Get-FileHash -LiteralPath $snapshot).Hash
        $result=Preview $snapshot; Assert ($result.Code -ne 0 -and $result.Text.Contains('ConvertFrom-Json'))
        Assert ((Get-FileHash -LiteralPath $snapshot).Hash -eq $hash)
    }
    Test 'S10 missing Preview exits nonzero without creating input' {
        $missing=Join-Path $storage 'no-preview.json'; $result=Preview $missing
        Assert ($result.Code -ne 0 -and $result.Text.Contains('does not exist') -and -not [IO.File]::Exists($missing))
    }
    Test 'S10 child default snapshot sentinel remains untouched and no report exists' {
        Assert ([IO.File]::ReadAllText($sentinel) -ceq 'default sentinel')
        Assert (-not [IO.File]::Exists($report))
    }
    Write-Host "Snapshot tests passed: $passed"
} finally {
    $absolute=[IO.Path]::GetFullPath($storage)
    if ([IO.Path]::GetDirectoryName($absolute) -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -and
        [IO.Path]::GetFileName($absolute) -match '^ResumeExplorer-SnapshotTests-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $absolute -Recurse -Force
    } else { throw 'UnsafeSnapshotTestCleanup' }
}
