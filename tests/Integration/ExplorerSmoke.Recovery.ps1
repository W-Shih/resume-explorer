# No side effects on import. Recovery never executes the generated commands.
function Get-SmokeRecoveryBase {
    $local=[Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($local)) { throw 'LocalApplicationDataUnavailable' }
    Join-Path $local 'ResumeExplorer\Snapshots\BeforeSmoke'
}
function Invoke-SmokeWorkerProcess($Engine,$Arguments) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$Engine; $info.UseShellExecute=$false
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
    $started=$false
    try {
        if (-not $process.Start()) { throw 'WorkerStartFailed' }
        $started=$true
        $process.WaitForExit()
        return $process.ExitCode
    } catch {
        if ($started -and -not $process.HasExited) { $_.Exception.Data['WorkerStillRunning']=$true }
        throw
    } finally {
        if ($started -and -not $process.HasExited) { Write-Warning "測試程序 $($process.Id) 可能仍在執行；請先確認已結束，再使用還原命令。" }
        $process.Dispose()
    }
}
function Get-SmokeRestoreCommand($Snapshot) {
    $engine=(Get-Process -Id $PID).Path.Replace("'","''")
    $entry=(Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'resume-explorer.ps1').Replace("'","''")
    "& '$engine' -NoProfile -Sta -File '$entry' -Action Restore -Snapshot '$($Snapshot.Replace("'","''"))'"
}
function Publish-SmokeRecovery($Source,$SuiteRoot,$Base,[string]$ExpectedHash='') {
    $id=[IO.Path]::GetFileName($SuiteRoot).Replace('ResumeExplorer-E2E-Suite-','')
    if ($id -notmatch '^[a-f0-9]{32}$') { throw 'InvalidRecoveryRunId' }
    $basePath=[IO.Path]::GetFullPath($Base)
    $cursor=[IO.DirectoryInfo]::new($basePath)
    while ($null -ne $cursor) {
        if ($cursor.Exists -and ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'RecoveryReparsePoint' }
        $cursor=$cursor.Parent
    }
    [void][IO.Directory]::CreateDirectory($basePath)
    $final=Join-Path $basePath ($id+'.json')
    $descriptor=Join-Path $basePath ($id+'.recovery.json')
    $note=Join-Path $basePath ($id+'.restore.txt')
    foreach ($file in @($final,$descriptor,$note)) { if (Test-Path -LiteralPath $file) { throw 'RecoveryAlreadyExists' } }
    $pending=Join-Path $basePath ('.'+$id+'.'+[guid]::NewGuid().ToString('N')+'.pending')
    $metaTemp=$pending+'.meta'; $noteTemp=$pending+'.txt'
    try {
        [IO.File]::Copy($Source,$pending,$false)
        $hash=(Get-FileHash -LiteralPath $pending).Hash
        if ($ExpectedHash -and $hash -ne $ExpectedHash) { throw 'ValidatedSnapshotChanged' }
        $command=Get-SmokeRestoreCommand $final
        $meta=[pscustomobject]@{ Version=1; RunId=$id; Snapshot=$final; SHA256=$hash; Validated=$true; SuiteRoot=$SuiteRoot }
        Write-SmokeJson $metaTemp $meta -New
        $stream=[IO.File]::Open($noteTemp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try {
            $bytes=[Text.Encoding]::UTF8.GetBytes("僅在 Snapshot 完整存在時使用。請在 PowerShell 7 執行；Restore 會新增視窗，請避免重複還原。`n$command`n")
            $stream.Write($bytes,0,$bytes.Length)
        } finally { $stream.Dispose() }
        [IO.File]::Move($metaTemp,$descriptor)
        [IO.File]::Move($noteTemp,$note)
        [IO.File]::Move($pending,$final) # Commit only after descriptor and instructions exist.
    } finally { foreach ($temporary in @($pending,$metaTemp,$noteTemp)) { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } } }
    Write-Host "已持久保存配置：$final"
    Write-Host "還原指令檔：$note"
    Write-Host $command
    return $final
}
function Show-SmokeRecovery($RunId,$Base,[string]$Status) {
    if ($RunId -notmatch '^[a-f0-9]{32}$') { throw 'InvalidRecoveryRunId' }
    $path=Join-Path $Base ($RunId+'.json')
    $metaPath=Join-Path $Base ($RunId+'.recovery.json')
    if (-not (Test-Path -LiteralPath $metaPath)) { return }
    Write-Host "測試結果：$Status"
    try {
        $meta=Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        if ($meta.Version -ne 1 -or $meta.RunId -ne $RunId -or -not $meta.Validated -or $meta.Snapshot -cne $path -or
            -not [IO.File]::Exists($path) -or (Get-FileHash -LiteralPath $path).Hash -ne $meta.SHA256) { throw 'RecoverySnapshotNotCommittedOrChanged' }
        $snapshot=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($snapshot.Version -ne 1 -or $null -eq $snapshot.Windows) { throw 'InvalidRecoverySnapshot' }
        Write-Host "測試前配置：$path"
        Write-Host '尚未自動還原。可能仍有原視窗或測試視窗，請先檢查，以免新增重複分組。'
        Write-Host '如需還原，請在 PowerShell 7 複製執行：'
        Write-Host (Get-SmokeRestoreCommand $path)
    } catch { Write-Warning "無法確認本次備份：$path；$($_.Exception.Message)" }
    Write-Host "還原指令檔：$(Join-Path $Base ($RunId+'.restore.txt'))"
}
