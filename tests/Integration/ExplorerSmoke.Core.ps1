# Task-5 harness only. Import defines functions and never observes/changes Explorer.
# Does not dot-source production core: observer and assertions are independent.
function Assert-Smoke($Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }

function Initialize-SmokeNative {
    if (-not ('ExplorerSmokeNative' -as [type])) {
        Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ExplorerSmokeNative {
 public delegate bool EnumWindowProc(IntPtr hwnd, IntPtr parameter);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowProc callback, IntPtr parameter);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder name, int size);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
 [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder name, int size, out int needed);
 [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr handle);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern IntPtr GetThreadDesktop(uint threadId);
}
'@
    }
}

function Get-SmokeRuntimeFacts {
    Assert-Smoke ([OperatingSystem]::IsWindows() -and $PSVersionTable.PSEdition -eq 'Core' -and
        $PSVersionTable.PSVersion.Major -eq 7 -and [Environment]::OSVersion.Version.Build -ge 22000 -and
        [Threading.Thread]::CurrentThread.ApartmentState -eq 'STA') 'RuntimeUnsupported'
    Initialize-SmokeNative
    $desktop=[ExplorerSmokeNative]::OpenInputDesktop(0,$false,1)
    $name=''; $accessible=$desktop -ne [IntPtr]::Zero
    if ($accessible) {
        try {
            $buffer=New-Object Text.StringBuilder 256; $needed=0
            $accessible=[ExplorerSmokeNative]::GetUserObjectInformation($desktop,2,$buffer,512,[ref]$needed)
            $name=$buffer.ToString()
        } finally { [void][ExplorerSmokeNative]::CloseDesktop($desktop) }
    }
    $session=(Get-Process -Id $PID).SessionId
    $threadDesktop=[ExplorerSmokeNative]::GetThreadDesktop([ExplorerSmokeNative]::GetCurrentThreadId())
    $currentName=New-Object Text.StringBuilder 256; $needed=0
    $currentAccessible=[ExplorerSmokeNative]::GetUserObjectInformation($threadDesktop,2,$currentName,512,[ref]$needed)
    [pscustomobject]@{
        Windows=[OperatingSystem]::IsWindows(); Build=[Environment]::OSVersion.Version.Build
        Edition=$PSVersionTable.PSEdition; Major=$PSVersionTable.PSVersion.Major; Version=$PSVersionTable.PSVersion.ToString()
        Apartment=[Threading.Thread]::CurrentThread.ApartmentState.ToString(); Interactive=[Environment]::UserInteractive
        SessionId=$session; ComputerName=$env:COMPUTERNAME; UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        DesktopAccessible=($accessible -and $currentAccessible); DesktopName=$name; CurrentDesktopName=$currentName.ToString()
    }
}

function Assert-SmokeSession($Facts, $Evidence) {
    Assert-Smoke ($Facts.Windows -and $Facts.Build -ge 22000 -and $Facts.Edition -eq 'Core' -and $Facts.Major -eq 7 -and $Facts.Apartment -eq 'STA') 'RuntimeUnsupported'
    Assert-Smoke ($Facts.Interactive -and $Facts.SessionId -gt 0 -and $Facts.DesktopAccessible -and
        $Facts.DesktopName -eq 'Default' -and $Facts.CurrentDesktopName -eq $Facts.DesktopName) 'SessionNotInteractive'
    Assert-Smoke ($Evidence.Kind -in @('DisposableVM','DedicatedTestAccount') -and
        $Evidence.ComputerName -eq $Facts.ComputerName -and $Evidence.UserSid -eq $Facts.UserSid -and
        $Evidence.SessionId -eq $Facts.SessionId -and $Evidence.DesktopName -eq $Facts.DesktopName -and
        $Evidence.Dedicated -eq $true -and -not [string]::IsNullOrWhiteSpace($Evidence.Notes)) 'SessionNotIsolated'
    # This is an operator attestation bound to real session facts, not automatic VM certification.
}

function Get-SmokeFingerprint([long]$Hwnd) {
    Initialize-SmokeNative
    Assert-Smoke ([ExplorerSmokeNative]::IsWindow([IntPtr]::new($Hwnd))) 'WindowGone'
    $root=[ExplorerSmokeNative]::GetAncestor([IntPtr]::new($Hwnd),2).ToInt64()
    [uint32]$processId=0
    [void][ExplorerSmokeNative]::GetWindowThreadProcessId([IntPtr]::new($root),[ref]$processId)
    $process=Get-Process -Id $processId -ErrorAction Stop
    Assert-Smoke ($root -gt 0 -and $process.ProcessName -eq 'explorer') 'WindowNotExplorer'
    [pscustomobject]@{ Hwnd=$Hwnd; RootHwnd=$root; PID=$processId; SessionId=$process.SessionId
        ProcessStartedAtUtc=$process.StartTime.ToUniversalTime().ToString('o') }
}

function Test-SmokeFingerprint($Left,$Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    foreach ($key in @('Hwnd','RootHwnd','PID','SessionId')) { if ($Left.$key -ne $Right.$key) { return $false } }
    try { return ([datetimeoffset]$Left.ProcessStartedAtUtc).UtcTicks -eq ([datetimeoffset]$Right.ProcessStartedAtUtc).UtcTicks }
    catch { return $false }
}

function Get-SmokeObservation {
    Initialize-SmokeNative
    $views=New-Object System.Collections.ArrayList; $errors=New-Object System.Collections.ArrayList; $seen=@{}
    try {
        $shell=New-Object -ComObject Shell.Application
        foreach ($window in $shell.Windows()) {
            try {
                if ([IO.Path]::GetFileName([string]$window.FullName) -ine 'explorer.exe') { continue }
                $hwnd=[long]$window.HWND; $fp=Get-SmokeFingerprint $hwnd
                $ptr=[Runtime.InteropServices.Marshal]::GetIUnknownForObject($window)
                try { $id=$ptr.ToInt64().ToString('X') } finally { [void][Runtime.InteropServices.Marshal]::Release($ptr) }
                Assert-Smoke (-not $seen.ContainsKey($id)) 'DuplicateOrConflictingIdentity'
                $seen[$id]=$true
                $path=[string]$window.Document.Folder.Self.Path
                Assert-Smoke (-not [string]::IsNullOrWhiteSpace($path)) 'UnreadablePath'
                [void]$views.Add([pscustomobject]@{ Identity=$id; RawHwnd=$hwnd; RootHwnd=$fp.RootHwnd
                    Path=$path; Fingerprint=$fp; Visible=[ExplorerSmokeNative]::IsWindowVisible([IntPtr]::new($fp.RootHwnd))
                    ComObject=$window }) # Retain RCW for this observer process's before/after comparison only.
            } catch { [void]$errors.Add([pscustomobject]@{ Message=$_.Exception.Message; HResult=$_.Exception.HResult }) }
        }
    } catch { [void]$errors.Add([pscustomobject]@{ Message=$_.Exception.Message; HResult=$_.Exception.HResult }) }
    # Cross-check COM exposure against top-level Explorer windows on this desktop.
    # This detects hidden/foreign Cabinet windows omitted by the COM view list.
    $topRoots=New-Object System.Collections.ArrayList
    $callback=[ExplorerSmokeNative+EnumWindowProc]{
        param([IntPtr]$handle,[IntPtr]$unused)
        $class=New-Object Text.StringBuilder 256
        [void][ExplorerSmokeNative]::GetClassName($handle,$class,256)
        if ($class.ToString() -in @('CabinetWClass','ExploreWClass')) { [void]$topRoots.Add($handle.ToInt64()) }
        return $true
    }
    $enumOk=[ExplorerSmokeNative]::EnumWindows($callback,[IntPtr]::Zero)
    $comRoots=@($views | ForEach-Object { $_.RootHwnd } | Sort-Object -Unique)
    if (-not $enumOk -or (@($topRoots | Sort-Object) -join ',') -cne ($comRoots -join ',')) {
        [void]$errors.Add([pscustomobject]@{ Message='TopLevelExplorerAndComScopeMismatch'; HResult=0 })
    }
    [pscustomobject]@{ Reliable=($errors.Count -eq 0); Views=@($views.ToArray()); Errors=@($errors.ToArray())
        ObservedAtUtc=[DateTime]::UtcNow.ToString('o'); ForegroundHwnd=[ExplorerSmokeNative]::GetForegroundWindow().ToInt64() }
}

function Assert-SmokeUia($Views) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    foreach ($view in @($Views | Group-Object RootHwnd | ForEach-Object { $_.Group[0] })) {
        $element=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]::new($view.RootHwnd))
        Assert-Smoke ($null -ne $element) 'UiaWindowUnavailable'
        $condition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'AddButton')
        $button=$element.FindFirst([System.Windows.Automation.TreeScope]::Subtree,$condition)
        Assert-Smoke ($null -ne $button) 'AddButtonUnavailable'
        $pattern=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        Assert-Smoke ($null -ne $pattern) 'InvokePatternUnavailable'
        # Read-only capability probe: never Invoke here, and do not guess TabItem/COM mappings.
    }
}

function ConvertTo-SmokeEvidence($Observation) {
    [pscustomobject]@{ Reliable=$Observation.Reliable; ObservedAtUtc=$Observation.ObservedAtUtc
        ForegroundHwnd=$Observation.ForegroundHwnd; Errors=@($Observation.Errors)
        Views=@($Observation.Views | Select-Object Identity,RawHwnd,RootHwnd,Path,Fingerprint,Visible) }
}

function Get-SmokePathKey($Paths) {
    # Multiset: sorting preserves duplicate requests. Test paths are dedicated non-root folders.
    # Length/structure must remain unambiguous when this key is itself grouped:
    # joining with a shared delimiter can confuse {A,A}|{C} with {A}|{A,C}.
    ConvertTo-Json -InputObject @($Paths | ForEach-Object { ([string]$_).TrimEnd('\').ToUpperInvariant() } | Sort-Object) -Compress
}

function Assert-SmokeScope($Observation,$ExpectedGroups,[int]$SessionId) {
    Assert-Smoke $Observation.Reliable 'ObservationIncomplete: 無法完整觀測 Explorer；請檢查 JSON Errors 與測試桌面的未知視窗，未繼續操作。'
    $views=@($Observation.Views)
    foreach ($view in $views) {
        Assert-Smoke ($view.Visible -and $view.Fingerprint.SessionId -eq $SessionId -and
            -not [string]::IsNullOrWhiteSpace($view.Identity) -and -not [string]::IsNullOrWhiteSpace($view.Path)) 'ForeignOrAmbiguousExplorer: 偵測到隱藏、其他 session 或身分／路徑不明的視窗；請檢查觀測證據後整理測試桌面。'
    }
    Assert-Smoke (@($views.Identity | Select-Object -Unique).Count -eq $views.Count) 'IdentityAmbiguous'
    $roots=@($views | Group-Object RootHwnd); $raw=@($views | Group-Object RawHwnd)
    Assert-Smoke ($roots.Count -eq $raw.Count) 'RawRootGroupingUnsupported'
    $actual=@($roots | ForEach-Object { Get-SmokePathKey $_.Group.Path } | Sort-Object)
    $expected=@($ExpectedGroups | ForEach-Object { Get-SmokePathKey $_.Paths } | Sort-Object)
    Assert-Smoke ($actual.Count -eq $expected.Count -and (Get-SmokePathKey $actual) -ceq (Get-SmokePathKey $expected)) (
        "ForeignOrAmbiguousExplorer: 實際 $($roots.Count) 個視窗／$($views.Count) 個分頁，預期 $($ExpectedGroups.Count) 個視窗且路徑分組須相符。請檢查觀測 JSON；若為啟動前的既有視窗，可用一鍵入口選擇儲存後關閉。測試中新增的未知視窗不會自動關閉。")
}

function Assert-SmokeOriginalUnchanged($Before,$After) {
    foreach ($old in $Before.Views) {
        $current=@($After.Views | Where-Object { $_.Identity -ceq $old.Identity })
        Assert-Smoke ($current.Count -eq 1 -and $current[0].RawHwnd -eq $old.RawHwnd -and
            $current[0].RootHwnd -eq $old.RootHwnd -and $current[0].Path -ieq $old.Path -and
            (Test-SmokeFingerprint $old.Fingerprint $current[0].Fingerprint)) 'OriginalFixtureChanged'
    }
}

function Write-SmokeJson([string]$Path,$Value,[switch]$New) {
    $json=ConvertTo-Json -InputObject $Value -Depth 24
    if ($New) {
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes=[Text.Encoding]::UTF8.GetBytes($json); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    } else {
        $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try {
            [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
            if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($temp,$Path) }
        } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
    }
}

function Assert-SmokeTempBase([string]$Temp) {
    $full=[IO.Path]::GetFullPath($Temp).TrimEnd('\')
    $production=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ResumeExplorer\Runs')).TrimEnd('\')
    Assert-Smoke ($full -ine $production -and -not $full.StartsWith($production+'\',[StringComparison]::OrdinalIgnoreCase)) 'ProductionRunsCannotBeTemp'
    $cursor=Get-Item -LiteralPath $Temp -Force
    while ($null -ne $cursor) {
        Assert-Smoke (-not ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'ReparseFixtureRoot'
        $cursor=$cursor.Parent
    }
}

function Assert-SmokeRoot([string]$Root,$Facts,[string]$Case) {
    $full=[IO.Path]::GetFullPath($Root); $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    Assert-Smoke ([IO.Path]::GetDirectoryName($full).TrimEnd('\') -ieq $temp -and
        [IO.Path]::GetFileName($full) -match '^ResumeExplorer-E2E-[a-f0-9]{32}$') 'UnsafeFixtureRoot'
    Assert-SmokeTempBase $temp
    $queue=New-Object 'System.Collections.Generic.Queue[string]'; $queue.Enqueue($full)
    while ($queue.Count) {
        $directory=$queue.Dequeue(); $entry=Get-Item -LiteralPath $directory -Force
        Assert-Smoke (-not ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'ReparseFixtureRoot'
        foreach ($child in @(Get-ChildItem -LiteralPath $directory -Force)) {
            Assert-Smoke (-not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'ReparseFixtureRoot'
            if ($child.PSIsContainer) { $queue.Enqueue($child.FullName) }
        }
    }
    $manifest=Get-Content -LiteralPath (Join-Path $full 'manifest.json') -Raw | ConvertFrom-Json
    Assert-Smoke ($manifest.Case -eq $Case -and $manifest.RunId -eq ([IO.Path]::GetFileName($full).Substring(19)) -and
        $manifest.ComputerName -eq $Facts.ComputerName -and $manifest.UserSid -eq $Facts.UserSid -and
        $manifest.SessionId -eq $Facts.SessionId) 'FixtureOwnershipMismatch'
    return $manifest
}

function Invoke-SmokeNativeCli($Arguments,[string]$LogPrefix) {
    $entry=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'resume-explorer.ps1'
    $engine=(Get-Process -Id $PID).Path
    $PSNativeCommandUseErrorActionPreference=$false
    & $engine -NoProfile -Sta -File $entry @Arguments 1>($LogPrefix+'.stdout.txt') 2>($LogPrefix+'.stderr.txt')
    return $LASTEXITCODE # synchronous, no hard wall-clock guarantee; never kill Explorer.
}

function New-SmokeAdapter {
    @{ Facts={ Get-SmokeRuntimeFacts }; Observe={ Get-SmokeObservation }; Uia={ param($views) Assert-SmokeUia $views }
        Cli={ param($arguments,$prefix) Invoke-SmokeNativeCli $arguments $prefix } }
}

function Assert-SmokeSnapshot($Snapshot,$Groups) {
    Assert-Smoke ($Snapshot.Version -eq 1) 'SnapshotVersionMismatch'
    $actual=@($Snapshot.Windows | ForEach-Object { Get-SmokePathKey $_.Paths } | Sort-Object)
    $expected=@($Groups | ForEach-Object { Get-SmokePathKey $_.Paths } | Sort-Object)
    Assert-Smoke ($actual.Count -eq $expected.Count -and (Get-SmokePathKey $actual) -ceq (Get-SmokePathKey $expected)) 'SnapshotFixtureMismatch'
}

function Assert-SmokeReport($Report,$Snapshot,[string[]]$Statuses) {
    Assert-Smoke ($Report.SchemaVersion -eq 1 -and $Report.State -eq 'Completed' -and
        @($Report.Items).Count -eq $Statuses.Count) 'ReportNotCompleted'
    $n=0; $groupIndex=0
    foreach ($group in $Snapshot.Windows) {
        $groupIndex++; $itemIndex=0
        foreach ($path in $group.Paths) {
            $itemIndex++
            $item=@($Report.Items | Where-Object { $_.GroupIndex -eq $groupIndex -and $_.ItemIndex -eq $itemIndex })
            Assert-Smoke ($item.Count -eq 1 -and $item[0].RequestedPath -ieq $path -and $item[0].Status -eq $Statuses[$n]) 'ReportItemMismatch'
            $n++
        }
    }
    Assert-Smoke ($n -eq $Statuses.Count) 'ReportCountMismatch'
}

function Invoke-SmokeCase($Context,$Adapter) {
    $root=$Context.TestRoot; $folder=Join-Path $root $Context.Case
    $a=Join-Path $folder 'A'; $b=Join-Path $folder 'B'; $c=Join-Path $folder 'C'
    $groups=@(); if ($Context.Case -eq 'E01') { $groups=@(@{ Paths=@($a,$b) },@{ Paths=@($c) }) }
    $snapshotPath=Join-Path $folder $(if ($Context.Case -eq 'E01') { 'capture.json' } else { 'retry-fixture.json' })
    $reportPath=Join-Path $folder $(if ($Context.Case -eq 'E01') { 'restore-root.json' } else { 'retry-root.json' })
    $resultPath=Join-Path $root 'smoke-result.json'
    $before=& $Adapter.Observe
    Assert-SmokeScope $before $groups $Context.Facts.SessionId
    $Context.Before=ConvertTo-SmokeEvidence $before
    foreach ($path in @($snapshotPath,$reportPath,(Join-Path $folder 'RetryRuns'))) { Assert-Smoke (-not (Test-Path -LiteralPath $path)) 'EvidencePathAlreadyExists' }
    $Context.Commands=@()
    $runCli={
        param($arguments,$name)
        # Validate the owned root again before each CLI call. Never retry a command.
        $null=Assert-SmokeRoot $root $Context.Facts $Context.Case
        $prefix=Join-Path $folder $name
        $command=[pscustomobject]@{ Name=$name; Arguments=$arguments; ExitCode=$null; StartedAtUtc=[DateTime]::UtcNow.ToString('o') }
        $Context.Commands+=$command; $Context.Phase=$name
        Write-SmokeJson $resultPath $Context
        $command.ExitCode=& $Adapter.Cli $arguments $prefix
        Write-SmokeJson $resultPath $Context
        Assert-Smoke ($command.ExitCode -eq 0) ('CliFailed:'+ $name)
    }
    if ($Context.Case -eq 'E01') {
        foreach ($path in @($a,$b,$c)) { Assert-Smoke ([IO.Directory]::Exists($path)) 'FixturePathMissing' }
        & $Adapter.Uia $before.Views
        $current=& $Adapter.Observe; Assert-SmokeScope $current $groups $Context.Facts.SessionId
        Assert-SmokeOriginalUnchanged $before $current
        & $runCli @('-Action','Capture','-Snapshot',$snapshotPath) '01-Capture'
        $snapshot=Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
        Assert-SmokeSnapshot $snapshot $groups
        $snapshotHash=(Get-FileHash -LiteralPath $snapshotPath).Hash
        & $runCli @('-Action','Preview','-Snapshot',$snapshotPath) '02-Preview'
        Assert-Smoke ((Get-FileHash -LiteralPath $snapshotPath).Hash -eq $snapshotHash) 'SnapshotChanged'
        $current=& $Adapter.Observe; Assert-SmokeScope $current $groups $Context.Facts.SessionId
        Assert-SmokeOriginalUnchanged $before $current
        & $runCli @('-Action','Restore','-Snapshot',$snapshotPath,'-ReportPath',$reportPath) '03-Restore'
        $report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        Assert-SmokeReport $report $snapshot @('Verified','Verified','Verified')
        Assert-Smoke ($report.SourceSnapshotHash -eq $snapshotHash) 'ReportSnapshotHashMismatch'
        Assert-Smoke ((Get-FileHash -LiteralPath $snapshotPath).Hash -eq $snapshotHash) 'SnapshotChanged'
        $after=& $Adapter.Observe; Assert-SmokeScope $after @($groups+$groups) $Context.Facts.SessionId
        Assert-SmokeOriginalUnchanged $before $after
        $new=@($after.Views | Where-Object { $_.RootHwnd -notin @($before.Views.RootHwnd) })
        Assert-Smoke ($new.Count -eq 3 -and @($new | Group-Object RootHwnd).Count -eq 2) 'NewWindowsMismatch'
        Assert-SmokeScope ([pscustomobject]@{ Reliable=$after.Reliable; Views=$new }) $groups $Context.Facts.SessionId
        foreach ($item in $report.Items) {
            Assert-Smoke (@($new | Where-Object { $_.Path -ieq $item.RequestedPath -and
                (Test-SmokeFingerprint $_.Fingerprint $item.WindowFingerprint) }).Count -eq 1) 'ReportWindowMismatch'
        }
        foreach ($group in @($report.Items | Group-Object GroupIndex)) {
            Assert-Smoke (@($group.Group.WindowFingerprint.RootHwnd | Select-Object -Unique).Count -eq 1) 'ReportGroupingMismatch'
        }
    } else {
        Assert-Smoke ([IO.Directory]::Exists($a) -and -not (Test-Path -LiteralPath $b)) 'MissingPathPreconditionViolated'
        $snapshot=[pscustomobject]@{ Version=1; CapturedAt=[DateTime]::UtcNow.ToString('o'); Windows=@([pscustomobject]@{ Paths=@($a,$b) }) }
        Write-SmokeJson $snapshotPath $snapshot -New
        $snapshotHash=(Get-FileHash -LiteralPath $snapshotPath).Hash
        & $runCli @('-Action','Restore','-Snapshot',$snapshotPath,'-ReportPath',$reportPath) '01-Restore'
        $parent=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        Assert-SmokeReport $parent $snapshot @('Verified','SkippedInvalidPath')
        Assert-Smoke ($parent.SourceSnapshotHash -eq $snapshotHash -and $parent.RootRunId -eq $parent.RunId -and
            -not $parent.ParentRunId -and $parent.RootReportPath -ieq $reportPath) 'RootLineageMismatch'
        $skip=$parent.Items[1]
        Assert-Smoke (-not ($skip.WindowCreateAttempted -or $skip.InvokeAttempted -or $skip.NavigateAttempted)) 'SkippedItemWasAttempted'
        $original=& $Adapter.Observe
        Assert-SmokeScope $original @(@{ Paths=@($a) }) $Context.Facts.SessionId
        $target=$original.Views[0]
        Assert-Smoke (Test-SmokeFingerprint $parent.Items[0].WindowFingerprint $target.Fingerprint) 'ReportWindowMismatch'
        & $Adapter.Uia $original.Views
        $parentHash=(Get-FileHash -LiteralPath $reportPath).Hash
        [void][IO.Directory]::CreateDirectory($b)
        & $runCli @('-Action','PreviewRetry','-ReportPath',$reportPath) '02-PreviewRetry'
        $sidecarPath=$reportPath+'.retry-preview.json'
        $sidecar=Get-Content -LiteralPath $sidecarPath -Raw | ConvertFrom-Json
        $selected=@($sidecar.Targets | Where-Object { Test-SmokeFingerprint $_ $target.Fingerprint })
        Assert-Smoke ($sidecar.RunId -eq $parent.RunId -and $sidecar.ReportHash -eq $parentHash -and
            $selected.Count -eq 1 -and @($sidecar.Targets).Count -eq 1) 'RetryPreviewMismatch'
        $sidecarHash=(Get-FileHash -LiteralPath $sidecarPath).Hash
        $fresh=& $Adapter.Observe; Assert-SmokeScope $fresh @(@{ Paths=@($a) }) $Context.Facts.SessionId
        Assert-SmokeOriginalUnchanged $original $fresh
        Assert-Smoke ((Get-FileHash -LiteralPath $reportPath).Hash -eq $parentHash) 'ParentReportChanged'
        & $runCli @('-Action','Retry','-ReportPath',$reportPath,'-GroupIndex','1','-ItemIndexes','2','-TargetHwnd',([string]$selected[0].Hwnd)) '03-Retry'
        Assert-Smoke ((Get-FileHash -LiteralPath $reportPath).Hash -eq $parentHash -and
            (Get-FileHash -LiteralPath $snapshotPath).Hash -eq $snapshotHash -and
            (Get-FileHash -LiteralPath $sidecarPath).Hash -eq $sidecarHash) 'SourceEvidenceChanged'
        $childFiles=@(Get-ChildItem -LiteralPath (Join-Path $folder 'RetryRuns') -Filter '*.json' -File)
        Assert-Smoke ($childFiles.Count -eq 1) 'RetryChildCountMismatch'
        $child=Get-Content -LiteralPath $childFiles[0].FullName -Raw | ConvertFrom-Json
        Assert-Smoke ($child.SchemaVersion -eq 1 -and $child.State -eq 'Completed' -and $child.ParentRunId -eq $parent.RunId -and
            $child.RootRunId -eq $parent.RootRunId -and $child.RootReportPath -ieq $parent.RootReportPath -and
            $child.SourceSnapshotHash -eq $snapshotHash -and @($child.Items).Count -eq 1) 'RetryLineageMismatch'
        $item=$child.Items[0]
        Assert-Smoke ($item.GroupIndex -eq 1 -and $item.ItemIndex -eq 2 -and $item.RequestedPath -ieq $b -and
            $item.Status -eq 'Verified' -and (Test-SmokeFingerprint $item.WindowFingerprint $target.Fingerprint)) 'RetryItemMismatch'
        $after=& $Adapter.Observe; Assert-SmokeScope $after @(@{ Paths=@($a,$b) }) $Context.Facts.SessionId
        Assert-SmokeOriginalUnchanged $original $after
        Assert-Smoke (@($after.Views.RootHwnd | Select-Object -Unique).Count -eq 1 -and $after.Views[0].RootHwnd -eq $target.RootHwnd) 'RetryTargetChanged'
        $Context.ParentHash=$parentHash
    }
    $Context.After=ConvertTo-SmokeEvidence $after
    $Context.EvidenceHashes=@(Get-ChildItem -LiteralPath $folder -File -Recurse | Where-Object { $_.Extension -eq '.json' } |
        ForEach-Object { [pscustomobject]@{ RelativePath=[IO.Path]::GetRelativePath($root,$_.FullName); SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash } })
    $Context.Status='AwaitingVisualReview'; $Context.Reason='IndependentObserverPassed-OperatorReviewRequired'; $Context.Phase='Review'
    $Context.($Context.Case)='AwaitingVisualReview'
}

function Invoke-ExplorerSmoke($Options,$Adapter) {
    $context=[pscustomobject]@{ HarnessVersion=1; Mode=$Options.Mode; Case=$Options.Case; Status='NotRun'; Reason='NotAuthorized'
        E01='NotRun'; E02='NotRun'; Facts=$null; SessionEvidence=$null; TestRoot=$Options.TestRoot; Phase='Consent'
        Before=$null; After=$null; Commands=@(); EvidenceHashes=@(); ParentHash=$null; VisualEvidence=$null; Error=$null }
    if (-not $Options.ConfirmIsolatedSession -or [string]::IsNullOrWhiteSpace($Options.SessionEvidence)) { return $context }
    if ($Options.Mode -eq 'Run' -and -not $Options.AllowExplorerUiChanges) { return $context }
    $saveResult=$false; $started=$false; $runLock=$null
    try {
        $context.Facts=& $Adapter.Facts
        $context.SessionEvidence=Get-Content -LiteralPath $Options.SessionEvidence -Raw | ConvertFrom-Json
        Assert-SmokeSession $context.Facts $context.SessionEvidence
        if ($Options.Mode -eq 'Prepare' -or $Options.Mode -eq 'Preflight') {
            $observation=& $Adapter.Observe
            Assert-SmokeScope $observation @() $context.Facts.SessionId
            & $Adapter.Uia @() # load managed UIA assemblies only, no controls yet
            $context.Before=ConvertTo-SmokeEvidence $observation
            if ($Options.Mode -eq 'Preflight') { $context.Status='Ready'; $context.Reason='ReadOnlyGatesPassed-E2ENotRun'; return $context }
            Assert-Smoke ([string]::IsNullOrWhiteSpace($Options.TestRoot)) 'PrepareRequiresNewRoot'
            Assert-SmokeTempBase ([IO.Path]::GetTempPath())
            $id=[guid]::NewGuid().ToString('N'); $root=Join-Path ([IO.Path]::GetTempPath()) ('ResumeExplorer-E2E-'+$id)
            Assert-Smoke (-not (Test-Path -LiteralPath $root)) 'FixtureAlreadyExists'
            [void][IO.Directory]::CreateDirectory($root); $context.TestRoot=$root
            $manifest=[pscustomobject]@{ RunId=$id; Case=$Options.Case; ComputerName=$context.Facts.ComputerName
                UserSid=$context.Facts.UserSid; SessionId=$context.Facts.SessionId; CreatedAtUtc=[DateTime]::UtcNow.ToString('o') }
            Write-SmokeJson (Join-Path $root 'manifest.json') $manifest -New; $saveResult=$true
            $folder=Join-Path $root $Options.Case
            [void][IO.Directory]::CreateDirectory((Join-Path $folder 'A'))
            if ($Options.Case -eq 'E01') { foreach ($name in @('B','C')) { [void][IO.Directory]::CreateDirectory((Join-Path $folder $name)) } }
            $context.Status='Prepared'; $context.Reason='ManualFixturesRequired-E2ENotRun'; return $context
        }
        $null=Assert-SmokeRoot $context.TestRoot $context.Facts $context.Case
        $resultPath=Join-Path $context.TestRoot 'smoke-result.json'
        # Harness-local lock prevents two invocations from consuming the same Prepared fixture.
        # It does not replace or bypass any production CLI lock.
        $runLock=[IO.File]::Open((Join-Path $context.TestRoot 'smoke-run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $previous=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        if ($Options.Mode -in @('Confirm','Verify')) {
            $manual=$Options.Mode -eq 'Confirm'
            Assert-Smoke ($previous.Status -eq 'AwaitingVisualReview' -and
                ((-not $manual) -or ($Options.ConfirmVisibleAndGrouping -and -not [string]::IsNullOrWhiteSpace($Options.VisualEvidence))) -and
                $previous.Case -eq $context.Case -and
                @($previous.EvidenceHashes).Count -gt 0 -and @($previous.After.Views).Count -gt 0) 'VisualReviewRequired'
            foreach ($hash in $previous.EvidenceHashes) {
                Assert-Smoke (-not [IO.Path]::IsPathRooted($hash.RelativePath) -and $hash.RelativePath -notmatch '(^|[\\/])\.\.([\\/]|$)') 'UnsafeEvidencePath'
                Assert-Smoke ((Get-FileHash -LiteralPath (Join-Path $context.TestRoot $hash.RelativePath)).Hash -eq $hash.SHA256) 'EvidenceChanged'
            }
            $now=& $Adapter.Observe; Assert-Smoke $now.Reliable 'ObservationIncomplete'
            # COM pointers are run-local: confirm in another process using roots/paths/fingerprints, not persisted IDs.
            $expectedGroups=@($previous.After.Views | Group-Object RootHwnd | ForEach-Object { @{ Paths=@($_.Group.Path) } })
            Assert-SmokeScope $now $expectedGroups $context.Facts.SessionId
            foreach ($view in $previous.After.Views) {
                Assert-Smoke (@($now.Views | Where-Object { $_.Path -ieq $view.Path -and (Test-SmokeFingerprint $_.Fingerprint $view.Fingerprint) }).Count -ge 1) 'ReviewWindowChanged'
            }
            $previous.Status='Passed'
            if ($manual) { $previous.Reason='ObserverAndOperatorVerified'; $previous.VisualEvidence=$Options.VisualEvidence }
            else { $previous.Reason='IndependentObserverVerified-VisualReviewNotRun'; $previous.VisualEvidence=$null }
            $previous | Add-Member -NotePropertyName VisualReview -NotePropertyValue $(if ($manual) { 'Passed' } else { 'NotRun' }) -Force
            $previous.($context.Case)='Passed'; Write-SmokeJson $resultPath $previous
            return $previous
        }
        Assert-Smoke ($Options.Mode -eq 'Run' -and $previous.Status -eq 'Prepared' -and $previous.Case -eq $context.Case) 'ReplayOrInvalidPhase'
        # Consume the run before the first possible CLI operation. Interrupted runs cannot be replayed.
        $context.Status='Running'; $saveResult=$true; Write-SmokeJson $resultPath $context; $started=$true
        Invoke-SmokeCase $context $Adapter
    } catch {
        $context.Status=$(if ($started -and $context.Commands.Count) { 'Failed' } else { 'Blocked' }); $context.Reason=$_.Exception.Message
        $context.Error=[pscustomobject]@{ Message=$_.Exception.Message; HResult=$_.Exception.HResult }
        if ($started) { $context.($context.Case)=$context.Status }
    } finally {
        try { if ($saveResult -and $Options.Mode -notin @('Confirm','Verify')) { Write-SmokeJson (Join-Path $context.TestRoot 'smoke-result.json') $context } }
        finally { if ($null -ne $runLock) { $runLock.Dispose() } }
    }
    return $context
}
