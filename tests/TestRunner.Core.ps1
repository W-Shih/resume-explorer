# Offline only. Import defines functions; it does not launch processes or create evidence.
function Get-OfflineTestManifest {
    @(
        @{ File='Issue2.Tests.ps1'; Expected=39 }
        @{ File='RestoreSummary.Tests.ps1'; Expected=17 }
        @{ File='ExplorerSmoke.Tests.ps1'; Expected=23 }
        @{ File='ExplorerSmoke.OneClick.Tests.ps1'; Expected=49 }
        @{ File='ExplorerSmoke.Recovery.Tests.ps1'; Expected=13 }
        @{ File='Snapshot.Tests.ps1'; Expected=18 }
        @{ File='TestRunner.Tests.ps1'; Expected=16 }
        @{ File='InstanceLock.Tests.ps1'; Expected=20 }
    )
}

function Get-OfflineTestEngine {
    $engine=(Get-Process -Id $PID -ErrorAction Stop).Path
    if (-not $IsWindows -or $PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -ne 7 -or
        [IO.Path]::GetFileName($engine) -ne 'pwsh.exe' -or -not [IO.File]::Exists($engine)) {
        throw 'OfflineTestsRequireWindowsPowerShell7: run with the current pwsh.exe engine.'
    }
    $engine
}

function Invoke-OfflineTestProcess([string]$Engine,[string]$Path) {
    $encoding=[Console]::OutputEncoding
    try {
        [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
        # Do not let caller native-error preferences turn a real child exit into a launch error.
        $PSNativeCommandUseErrorActionPreference=$false
        $output=@(& $Engine -NoProfile -NonInteractive -File $Path 2>&1)
        $code=$LASTEXITCODE
        [pscustomobject]@{ RawExitCode=$code; Lines=@($output | ForEach-Object { $_.ToString() }) }
    } finally { [Console]::OutputEncoding=$encoding }
}

function Invoke-OfflineTestCollector {
    param([object[]]$Manifest,[string]$TestsRoot,[string]$Engine,[switch]$FailFast,
        [scriptblock]$Launch={ param($engine,$path) Invoke-OfflineTestProcess $engine $path })
    if (-not $Manifest.Count) { throw 'InvalidOfflineManifest: empty manifest.' }
    $names=@{}
    foreach ($suite in $Manifest) {
        if ($suite.File -isnot [string] -or $suite.File -notmatch '^[\w.-]+\.ps1$' -or
            $suite.Expected -isnot [int] -or $suite.Expected -le 0 -or $names.ContainsKey($suite.File)) {
            throw 'InvalidOfflineManifest: unique literal filenames and positive integer counts required.'
        }
        $names[$suite.File]=$true
    }
    $stopped=$false
    foreach ($suite in $Manifest) {
        $row=[pscustomobject]@{ Name=$suite.File; Expected=$suite.Expected; ObservedPassed=0
            RawExitCode=$null; Status='NotRun'; Reason='FailFast'; LogPath=$null; Output=@() }
        if (-not $stopped) {
            try {
                $path=Join-Path $TestsRoot $suite.File
                if (-not [IO.File]::Exists($path)) { throw "SuiteNotFound: $path" }
                $result=& $Launch $Engine $path
                if ($null -eq $result.RawExitCode) { throw 'ChildExitUnavailable' }
                $row.RawExitCode=$result.RawExitCode
                $row.Output=@($result.Lines)
                $passes=@($row.Output | Where-Object { $_.StartsWith('PASS ') })
                $row.ObservedPassed=$passes.Count
                $unique=@($passes | Select-Object -Unique).Count
                if ($row.RawExitCode -eq 0 -and $passes.Count -eq $suite.Expected -and $unique -eq $passes.Count) {
                    $row.Status='Passed'; $row.Reason=$null
                } else {
                    $row.Status='Failed'; $row.Reason='ExitOrPassCountMismatch'
                    if ($unique -ne $passes.Count) { $row.Reason='DuplicatePassLines' }
                }
            } catch {
                $row.Status='Error'; $row.Reason=$_.Exception.Message
                $row.Output=@($_.ToString(),$_.ScriptStackTrace)
            }
            if ($FailFast -and $row.Status -ne 'Passed') { $stopped=$true }
        }
        $row
    }
}

function Save-OfflineTestEvidence($Run,[string]$Directory) {
    # The caller owns a newly reserved directory. Never reuse an old result or log.
    foreach ($row in $Run.Suites) {
        $row.LogPath=Join-Path $Directory ($row.Name+'.log')
        $stream=[IO.File]::Open($row.LogPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false))
            try { foreach ($line in $row.Output) { $writer.WriteLine($line) } } finally { $writer.Dispose() }
        } finally { $stream.Dispose() }
    }
    $summary=[ordered]@{}
    foreach ($key in $Run.Keys) { if ($key -ne 'Suites') { $summary[$key]=$Run[$key] } }
    $summary.Suites=@($Run.Suites | Select-Object Name,Expected,ObservedPassed,RawExitCode,Status,Reason,LogPath)
    $json=ConvertTo-Json -InputObject $summary -Depth 8
    $path=Join-Path $Directory 'result.json'
    $staging=Join-Path $Directory 'result.json.partial'
    $stream=[IO.File]::Open($staging,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false))
        try { $writer.Write($json) } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
    # Publish only after every required log and the entire JSON have been closed.
    [IO.File]::Move($staging,$path)
}

function Invoke-OfflineTestRun {
    param([switch]$FailFast)
    $run=[ordered]@{ Version=1; RunId=[guid]::NewGuid().ToString('N'); StartedAtUtc=[DateTime]::UtcNow.ToString('o')
        CompletedAtUtc=$null; EnginePath=$null; PSVersion=$PSVersionTable.PSVersion.ToString()
        OSVersion=[Environment]::OSVersion.VersionString; OverallStatus='Error'; Reason=$null
        E2E=@{ Status='NotRun'; Reason='OfflineOnly' }; Suites=@() }
    $directory=$null; $exitCode=2; $reserved=$false; $saving=$false
    try {
        $run.EnginePath=Get-OfflineTestEngine
        $directory=Join-Path ([IO.Path]::GetTempPath()) ('ResumeExplorer-OfflineTests-'+$run.RunId)
        # Reserve the unique owner before writing anything; an existing path is an error.
        $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
        $reserved=$true
        $run.Suites=@(Invoke-OfflineTestCollector -Manifest @(Get-OfflineTestManifest) -TestsRoot $PSScriptRoot -Engine $run.EnginePath -FailFast:$FailFast)
        $exitCode=0; $run.OverallStatus='Passed'
        if (@($run.Suites | Where-Object Status -ne 'Passed').Count) { $exitCode=1; $run.OverallStatus='Failed' }
        if (@($run.Suites | Where-Object Status -eq 'Error').Count) { $exitCode=2; $run.OverallStatus='Error' }
        $run.CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
        $saving=$true
        Save-OfflineTestEvidence $run $directory
    } catch {
        $exitCode=2; $run.OverallStatus='Error'; $run.Reason=$_.Exception.Message
        $run.CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
        Write-Host "Offline runner error: $($run.Reason)"
        # Collection/manifest failures can still have a useful Error report.
        # Do not retry evidence writes or replace their original exception.
        if ($reserved -and -not $saving) {
            try { Save-OfflineTestEvidence $run $directory }
            catch { Write-Host "Offline evidence error: $($_.Exception.Message)" }
        }
    }
    if ($directory) { Write-Host "Offline evidence: $directory" }
    [pscustomobject]@{ ExitCode=$exitCode; Run=$run; EvidencePath=$directory }
}
