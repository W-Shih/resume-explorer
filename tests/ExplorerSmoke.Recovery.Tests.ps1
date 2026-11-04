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
try {
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
