$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Integration/ExplorerSmoke.OneClick.Core.ps1')
$storage=Join-Path $env:TEMP ('SmokeRecoveryTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($storage)
$passed=0
function Assert($Condition) { if (-not $Condition) { throw 'Recovery assertion failed' } }
function Test($Name,$Body) { & $Body; $script:passed++; Write-Host "PASS $Name" }
function New-RecoveryFixture {
    $id=[guid]::NewGuid().ToString('N')
    $source=Join-Path $storage ($id+'.source')
    Write-SmokeJson $source @{ Version=1; Windows=@(@{ Paths=@('C:\A','C:\B') }) } -New
    @{ Id=$id; Source=$source; Suite=(Join-Path $env:TEMP ('ResumeExplorer-E2E-Suite-'+$id)); Base=(Join-Path $storage "Before Smoke's 資料") }
}
function Invoke-SupervisorFixture($Mode,[int]$RawCode=0,[bool]$StillRunning=$false) {
    $folder=Join-Path $storage ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($folder)
    $entry=Join-Path $folder 'Start-ExplorerSmoke.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Integration/Start-ExplorerSmoke.ps1') -Destination $entry
    $recovery=(Join-Path $PSScriptRoot 'Integration/ExplorerSmoke.Recovery.ps1').Replace("'","''")
    $core=(Join-Path $PSScriptRoot 'Integration/ExplorerSmoke.Core.ps1').Replace("'","''")
    # Replace only external dependencies, run the unchanged public entry and real recovery formatter.
    $stub=". '$core'`n. '$recovery'`n"+@'
function Get-SmokeRecoveryBase { Join-Path $PSScriptRoot 'BeforeSmoke' }
function Invoke-SmokeWorkerProcess {
    param($Engine,$Arguments)
    $id=$Arguments[[Array]::IndexOf($Arguments,'-RunId')+1]
    $source=Join-Path $PSScriptRoot 'source.json'
    Write-SmokeJson $source @{Version=1; Windows=@(@{Paths=@('C:\synthetic')})} -New
    $null=Publish-SmokeRecovery $source (Join-Path $PSScriptRoot ('ResumeExplorer-E2E-Suite-'+$id)) (Get-SmokeRecoveryBase)
    if (STILL_RUNNING) {
        $exception=[InvalidOperationException]::new('SyntheticWaitInterrupted')
        $exception.Data['WorkerStillRunning']=$true
        throw $exception
    }
    return RAW_CODE
}
function Get-Content {
    param($LiteralPath,[switch]$Raw)
    if ($LiteralPath.EndsWith('suite-result.json')) {
        switch ('RESULT_MODE') {
            Missing { throw 'SyntheticSuiteMissing' }
            Malformed { return '{' }
            default { return ('{"Status":"'+ 'RESULT_MODE' +'"}') }
        }
    }
    Microsoft.PowerShell.Management\Get-Content -LiteralPath $LiteralPath -Raw:$Raw
}
'@
    $stub=$stub.Replace('RESULT_MODE',$Mode).Replace('RAW_CODE',[string]$RawCode).Replace('STILL_RUNNING',('$'+$StillRunning.ToString().ToLowerInvariant()))
    [IO.File]::WriteAllText((Join-Path $folder 'ExplorerSmoke.OneClick.Core.ps1'),$stub)
    $engine=(Get-Process -Id $PID).Path
    $output=@(& $engine -NoProfile -NonInteractive -File $entry -Run 2>&1)
    $code=$LASTEXITCODE; $text=$output -join "`n"
    $notice=$text.LastIndexOf('測試結果：')
    return @{ Code=$code; Text=$text; Summary=$(if ($notice -ge 0) { $text.Substring($notice) } else { '' }) }
}
try {
    Test 'public supervisor rejects missing malformed and unsuccessful results but keeps recovery commands' {
        foreach ($mode in @('Missing','Malformed','Running','Failed','Passed')) {
            $result=Invoke-SupervisorFixture $mode
            $expected=1; if ($mode -eq 'Passed') { $expected=0 }
            Assert ($result.Code -eq $expected -and $result.Summary.Contains('-Action Restore'))
            if ($expected -eq 1) {
                if ($result.Text.Contains('測試結果：Passed')) { throw "A01 reproduced: $mode returns Exit 1 but displays Passed" }
                Assert ($result.Text.Contains('測試結果：Failed／結果不明 (Exit 1)'))
            }
            else { Assert ($result.Text.Contains('測試結果：Passed')) }
        }
    }
    Test 'public supervisor preserves nonzero exits and live-worker warning with recovery commands' {
        foreach ($code in @(1,2,3,17)) {
            $result=Invoke-SupervisorFixture 'Passed' $code
            $expected=$code; if ($code -eq 17) { $expected=1 }
            Assert ($result.Code -eq $expected -and -not $result.Text.Contains('測試結果：Passed') -and $result.Summary.Contains('-Action Restore'))
            Assert ($result.Text.Contains("Exit $code"))
        }
        $result=Invoke-SupervisorFixture 'Passed' 0 $true
        Assert ($result.Code -eq 1 -and $result.Text.Contains('測試程序可能仍在執行') -and $result.Text.Contains('SyntheticWaitInterrupted'))
        Assert (-not $result.Text.Contains('測試結果：Passed') -and $result.Summary.Contains('-Action Restore'))
    }
    Test 'persistent publication commits exact bytes with instructions and descriptor' {
        $f=New-RecoveryFixture; $path=Publish-SmokeRecovery $f.Source $f.Suite $f.Base
        Assert ((Get-FileHash $path).Hash -eq (Get-FileHash $f.Source).Hash)
        Assert (Test-Path -LiteralPath (Join-Path $f.Base ($f.Id+'.restore.txt')))
        $text=@(Show-SmokeRecovery $f.Id $f.Base 'Passed' 6>&1) -join "`n"
        Assert ($text.Contains('-Action Restore') -and $text.Contains('Passed') -and $text.Contains("Smoke''s"))
    }
    Test 'repeated publication cannot overwrite any committed snapshot' {
        $f=New-RecoveryFixture; $path=Publish-SmokeRecovery $f.Source $f.Suite $f.Base
        $hash=(Get-FileHash $path).Hash; $caught=$false
        try { Publish-SmokeRecovery $f.Source $f.Suite $f.Base } catch { $caught=$true }
        Assert ($caught -and (Get-FileHash $path).Hash -eq $hash)
    }
    Test 'saved recovery survives missing suite result for all terminal statuses' {
        $f=New-RecoveryFixture; $null=Publish-SmokeRecovery $f.Source $f.Suite $f.Base
        foreach ($status in @('Passed','Failed','Cancelled','Crashed')) {
            $text=@(Show-SmokeRecovery $f.Id $f.Base $status 6>&1) -join "`n"
            Assert ($text.Contains($status) -and $text.Contains('-Action Restore'))
        }
    }
    Test 'changed or missing snapshot is diagnosed without a trusted executable command' {
        $f=New-RecoveryFixture; $path=Publish-SmokeRecovery $f.Source $f.Suite $f.Base
        [IO.File]::AppendAllText($path,' ')
        $text=@(Show-SmokeRecovery $f.Id $f.Base 'Failed' 6>&1 3>&1) -join "`n"
        Assert (-not $text.Contains('-Action Restore') -and $text.Contains('無法確認'))
    }
    Test 'incomplete commit and another run never yield a restore command' {
        $f=New-RecoveryFixture
        Assert (@(Show-SmokeRecovery $f.Id $f.Base 'Cancelled' 6>&1).Count -eq 0)
        $null=Publish-SmokeRecovery $f.Source $f.Suite $f.Base
        $other=[guid]::NewGuid().ToString('N')
        Assert (@(Show-SmokeRecovery $other $f.Base 'Failed' 6>&1).Count -eq 0)
        Remove-Item -LiteralPath (Join-Path $f.Base ($f.Id+'.json'))
        $text=@(Show-SmokeRecovery $f.Id $f.Base 'Crashed' 6>&1 3>&1) -join "`n"
        Assert (-not $text.Contains('-Action Restore') -and $text.Contains('無法確認'))
    }
    Test 'descriptor write failure leaves no final snapshot' {
        $f=New-RecoveryFixture; $write=${function:Write-SmokeJson}; $caught=$false
        & {
            function Write-SmokeJson { param($Path,$Value,[switch]$New) throw 'SyntheticDescriptorFailure' }
            try { Publish-SmokeRecovery $f.Source $f.Suite $f.Base } catch { $script:publicationFailed=$true }
        }
        Assert ($script:publicationFailed -and -not (Test-Path -LiteralPath (Join-Path $f.Base ($f.Id+'.json'))))
    }
    Test 'worker immediate exit bypasses finally while parent retains committed recovery' {
        $f=New-RecoveryFixture; $null=Publish-SmokeRecovery $f.Source $f.Suite $f.Base
        $fixture=Join-Path $storage 'exit worker.ps1'
        [IO.File]::WriteAllText($fixture,'try { [Environment]::Exit(17) } finally { throw "must not run" }')
        $code=Invoke-SmokeWorkerProcess (Get-Process -Id $PID).Path @('-NoProfile','-File',$fixture)
        Assert ($code -eq 17)
        $text=@(Show-SmokeRecovery $f.Id $f.Base 'Crashed:17' 6>&1) -join "`n"
        Assert ($text.Contains('Crashed:17') -and $text.Contains('-Action Restore'))
    }
    Test 'restore command quotes literal special characters without executing them' {
        $command=Get-SmokeRestoreCommand "C:\A's 資料\`$(never-run)&(x)\snapshot.json"
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseInput($command,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0 -and $command.Contains("A''s") -and $command.Contains('$(never-run)&(x)'))
    }
    Test 'worker arguments and normal exit codes survive the foreground process boundary' {
        $fixture=Join-Path $storage 'argument worker.ps1'
        [IO.File]::WriteAllText($fixture,'param($Value,[int]$Code) if ($Value -cne "中文 space & literal") { exit 99 }; exit $Code')
        foreach ($code in @(0,1,2,3)) {
            $actual=Invoke-SmokeWorkerProcess (Get-Process -Id $PID).Path @('-NoProfile','-File',$fixture,'-Value','中文 space & literal','-Code',[string]$code)
            Assert ($actual -eq $code)
        }
    }
    Test 'content changed after validation cannot be committed' {
        $f=New-RecoveryFixture; $caught=$false
        try { Publish-SmokeRecovery $f.Source $f.Suite $f.Base 'wrong-validated-hash' } catch { $caught=$_.Exception.Message -eq 'ValidatedSnapshotChanged' }
        Assert ($caught -and -not (Test-Path -LiteralPath (Join-Path $f.Base ($f.Id+'.json'))))
    }
} finally {
    $full=[IO.Path]::GetFullPath($storage)
    Assert ([IO.Path]::GetDirectoryName($full) -ieq [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\'))
    Assert ([IO.Path]::GetFileName($full) -like 'SmokeRecoveryTests-*')
    Remove-Item -LiteralPath $full -Recurse -Force
}
Write-Host "$passed recovery tests passed; no Explorer operations."
