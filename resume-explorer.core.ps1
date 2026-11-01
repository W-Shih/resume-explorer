# Internal core: dot-sourcing defines functions only; it never starts Explorer.
$script:ResumeExplorerVersion = '0.1.0-beta.1+issue2'

function Assert-RestoreConfig($Config) {
    foreach ($key in @('DetectionTimeoutSeconds','PollIntervalMs','StableDurationMs','BaselineTimeoutSeconds','NavigationTimeoutSeconds')) {
        if ($Config[$key] -le 0) { throw "Invalid configuration: $key must be positive." }
    }
    if (@($Config.TransientErrorBackoffMs).Count -eq 0 -or @($Config.TransientErrorBackoffMs | Where-Object { $_ -le 0 }).Count) {
        throw 'TransientErrorBackoffMs must contain positive delays.'
    }
}

function Initialize-ExplorerNative {
    if (-not ('ResumeExplorerNative' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ResumeExplorerNative {
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
}
'@
    }
}

function Get-WindowFingerprint([long]$Hwnd) {
    Initialize-ExplorerNative
    $handle = [IntPtr]::new($Hwnd)
    if (-not [ResumeExplorerNative]::IsWindow($handle)) { throw 'WindowGone' }
    $root = [ResumeExplorerNative]::GetAncestor($handle, 2).ToInt64()
    if ($root -le 0) { throw 'WindowGone' }
    [uint32]$processId = 0
    [void][ResumeExplorerNative]::GetWindowThreadProcessId([IntPtr]::new($root), [ref]$processId)
    $process = Get-Process -Id $processId -ErrorAction Stop
    if ($process.ProcessName -ine 'explorer') { throw 'WindowNotExplorer' }
    [pscustomobject]@{
        Hwnd=$Hwnd; RootHwnd=$root; PID=$processId
        ProcessStartedAtUtc=$process.StartTime.ToUniversalTime().ToString('o'); SessionId=$process.SessionId
    }
}

function Test-FingerprintEqual($Left, $Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    foreach ($name in @('Hwnd','RootHwnd','PID','SessionId')) {
        if ($Left.$name -ne $Right.$name) { return $false }
    }
    # PowerShell 7 can deserialize ISO JSON timestamps as DateTime, unlike 5.1.
    try {
        $times=@(foreach ($value in @($Left.ProcessStartedAtUtc,$Right.ProcessStartedAtUtc)) {
            if ($value -is [datetime]) { $value.ToUniversalTime().Ticks }
            else { ([DateTimeOffset]::Parse([string]$value,[Globalization.CultureInfo]::InvariantCulture)).UtcDateTime.Ticks }
        })
        if ($times[0] -ne $times[1]) { return $false }
    } catch { return $false }
    return $true
}

function Get-TabIdentity($Tab) {
    $ptr = [Runtime.InteropServices.Marshal]::GetIUnknownForObject($Tab)
    try { $ptr.ToInt64().ToString('X') }
    finally { [void][Runtime.InteropServices.Marshal]::Release($ptr) }
}

function Get-ExplorerObservation {
    $views = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $enumerated = $false; $reliable = $true; $rawCount = 0; $seen = @{}; $shellAvailable=$false
    try {
        $shell = New-Object -ComObject Shell.Application
        $shellAvailable=$true
        $windows = $shell.Windows()
        foreach ($window in $windows) {
            $stage = 'FullName'; $hwnd = $null
            try {
                if ([IO.Path]::GetFileName([string]$window.FullName) -ine 'explorer.exe') { continue }
                $rawCount++; $stage = 'HWND'; $hwnd = [long]$window.HWND
                $fingerprint = Get-WindowFingerprint $hwnd
                $stage = 'Identity'; $id = Get-TabIdentity $window
                $path = ''; $readable = $true
                try { $path = [string]$window.Document.Folder.Self.Path }
                catch {
                    $readable = $false
                    [void]$errors.Add([pscustomobject]@{ Stage='Path'; HResult=$_.Exception.HResult; Message=$_.Exception.Message; KnownHwnd=$hwnd })
                }
                $view = [pscustomobject]@{ RawHwnd=$hwnd; HWND=$hwnd; RootHwnd=$fingerprint.RootHwnd; PID=$fingerprint.PID
                    Identity=$id; Path=$path; PathReadable=$readable; ComObject=$window; Fingerprint=$fingerprint }
                if ($seen.ContainsKey($id)) {
                    if ($seen[$id].RawHwnd -ne $hwnd -or $seen[$id].RootHwnd -ne $view.RootHwnd -or $seen[$id].PID -ne $view.PID) {
                        $reliable = $false
                        [void]$errors.Add([pscustomobject]@{ Stage='IdentityConflict'; HResult=0; Message='Conflicting duplicate identity'; KnownHwnd=$hwnd })
                    }
                } else { $seen[$id]=$view; [void]$views.Add($view) }
            } catch {
                $reliable = $false
                [void]$errors.Add([pscustomobject]@{ Stage=$stage; HResult=$_.Exception.HResult; Message=$_.Exception.Message; KnownHwnd=$hwnd })
            }
        }
        $enumerated = $true
    } catch {
        $reliable = $false
        [void]$errors.Add([pscustomobject]@{ Stage='Enumeration'; HResult=$_.Exception.HResult; Message=$_.Exception.Message; KnownHwnd=$null })
    }
    [pscustomobject]@{ ObservedAtUtc=[DateTime]::UtcNow.ToString('o'); Views=@($views.ToArray()); ReadErrors=@($errors.ToArray())
        EnumerationSucceeded=$enumerated; GlobalUnavailable=(-not $shellAvailable)
        IdentitySetReliable=($enumerated -and $reliable); RawCount=$rawCount; UniqueCount=$views.Count }
}

function New-ExplorerAdapter {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    @{
        Now={ $clock.Elapsed.TotalMilliseconds }.GetNewClosure()
        Sleep={ param($ms) Start-Sleep -Milliseconds ([int][Math]::Ceiling($ms)) }
        Observe={ Get-ExplorerObservation }
        Fingerprint={ param($hwnd) Get-WindowFingerprint $hwnd }
        PrepareInvoke={ param($hwnd) Get-NewTabInvokePattern $hwnd }
        Invoke={ param($pattern) $pattern.Invoke() }
        Navigate={ param($view,$path) $view.ComObject.Navigate2([string]$path) }
        # Restore requests visible windows. Hidden is not a background/no-focus implementation.
        OpenWindow={ param($path) Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList ('"' + $path + '"') -WindowStyle Normal }
        PathExists={ param($path) [IO.Directory]::Exists($path) }
    }
}

function Get-NewTabInvokePattern([long]$Hwnd) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    # Keep the original raw-HWND grouping model. Root HWND is only the UIA lookup surface.
    $fp = Get-WindowFingerprint $Hwnd
    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]::new($fp.RootHwnd))
    if ($null -eq $root) { throw 'UIAutomationUnavailable' }
    $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'AddButton')
    $button = $root.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $condition)
    if ($null -eq $button) { throw 'AddButtonNotFound' }
    $pattern = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    if ($null -eq $pattern) { throw 'InvokePatternUnavailable' }
    return $pattern
}

function Test-TargetWindow($Adapter, $Fingerprint) {
    try { Test-FingerprintEqual $Fingerprint (& $Adapter.Fingerprint $Fingerprint.Hwnd) }
    catch { $false }
}

function Get-TargetViews($Observation, $Fingerprint) {
    # Do not silently change Capture's HWND grouping to RootHwnd without VDI evidence.
    @($Observation.Views | Where-Object { $_.RawHwnd -eq $Fingerprint.Hwnd } | Group-Object Identity | ForEach-Object { $_.Group[0] })
}

function Wait-Poll($Adapter, [double]$Deadline, [double]$Delay) {
    $remaining = $Deadline - (& $Adapter.Now)
    if ($remaining -gt 0) { & $Adapter.Sleep ([Math]::Min($remaining,$Delay)) }
}

function Wait-StableTabBaseline($Adapter, $Fingerprint, $Config, $Diagnostics) {
    $start=(& $Adapter.Now); $deadline = $start + 1000 * $Config.BaselineTimeoutSeconds
    $previous = $null; $since = 0; $count = 0
    while ((& $Adapter.Now) -lt $deadline) {
        if (-not (Test-TargetWindow $Adapter $Fingerprint)) { return @{ Reason='WindowGone' } }
        $obs = & $Adapter.Observe
        if ($null -ne $Diagnostics) { Add-ObservationDiagnostic $Diagnostics $obs ((& $Adapter.Now)-$start) 'Baseline' }
        if ($obs.GlobalUnavailable) { throw 'ShellUnavailable' }
        $views = @(Get-TargetViews $obs $Fingerprint)
        $key = (@($views.Identity | Sort-Object) -join ',')
        if ($obs.IdentitySetReliable -and $views.Count -gt 0) {
            if ($null -eq $previous -or $key -cne $previous) { $previous=$key; $since=(& $Adapter.Now); $count=1 }
            else { $count++ }
            if ($count -ge 3 -and ((& $Adapter.Now)-$since) -ge $Config.StableDurationMs) {
                return @{ Reason='Stable'; Views=$views; Ids=@($views.Identity); Observation=$obs }
            }
        } else { $previous=$null; $count=0 }
        Wait-Poll $Adapter $deadline $Config.PollIntervalMs
    }
    return @{ Reason='BaselineUnstable' }
}

function Resolve-NewTabCandidate($BaselineIds, $Views, $Seen) {
    $ids = @($Views.Identity | Sort-Object -Unique)
    if (@($BaselineIds | Where-Object { $_ -notin $ids }).Count) { return @{ State='Invalid'; Reason='IdentityChanged' } }
    $new = @($Views | Where-Object { $_.Identity -notin $BaselineIds } | Group-Object Identity | ForEach-Object { $_.Group[0] })
    foreach ($view in $new) { $Seen[$view.Identity]=$view } # RCWs live for the transaction.
    if ($Seen.Count -gt 1) { return @{ State='Ambiguous'; Reason='AmbiguousCandidates' } }
    if ($new.Count -eq 1) { return @{ State='Unique'; View=$new[0] } }
    return @{ State='Pending'; Reason='NoCandidateObserved' }
}

function New-DetectionDiagnostics($Config) {
    [ordered]@{
        DetectionTimeoutSecondsConfigured=$Config.DetectionTimeoutSeconds; PollIntervalMsConfigured=$Config.PollIntervalMs
        TransientErrorBackoffMsConfigured=@($Config.TransientErrorBackoffMs); PollCount=0; TransientReadErrorCount=0
        MaxConsecutiveReadErrors=0; DetectionElapsedMs=0; SeenCandidateCount=0; LastObservationError=$null
        Samples=@()
    }
}

function Add-ObservationDiagnostic($Diagnostics, $Observation, $Elapsed, [string]$Phase='Detection') {
    $Diagnostics.Samples += [pscustomobject]@{
        ElapsedMs=[int]$Elapsed; Phase=$Phase; ObservedAtUtc=$Observation.ObservedAtUtc
        Reliable=$Observation.IdentitySetReliable; RawCount=$Observation.RawCount; UniqueCount=$Observation.UniqueCount
        Views=@($Observation.Views | Select-Object RawHwnd,RootHwnd,PID,Identity,Path,PathReadable,Fingerprint)
        Errors=@($Observation.ReadErrors)
    }
}

function Wait-NewTabCandidate($Adapter, $Fingerprint, $Baseline, $Config, $Diagnostics) {
    $start = & $Adapter.Now; $deadline=$start + 1000*$Config.DetectionTimeoutSeconds
    $seen=@{}; $stableId=$null; $since=0; $streak=0; $reason='NoCandidateObserved'; $candidate=$null
    try {
        while ((& $Adapter.Now) -lt $deadline) {
            if (-not (Test-TargetWindow $Adapter $Fingerprint)) { $reason='WindowGone'; break }
            $obs = & $Adapter.Observe; $Diagnostics.PollCount++
            Add-ObservationDiagnostic $Diagnostics $obs ((& $Adapter.Now)-$start)
            if ($obs.GlobalUnavailable) { throw 'ShellUnavailable' }
            if (-not $obs.IdentitySetReliable) {
                $stableId=$null; $streak++; $Diagnostics.TransientReadErrorCount++
                $Diagnostics.MaxConsecutiveReadErrors=[Math]::Max($streak,$Diagnostics.MaxConsecutiveReadErrors)
                $Diagnostics.LastObservationError=@($obs.ReadErrors); $reason='ObservationIncomplete'
                $delay=$Config.TransientErrorBackoffMs[[Math]::Min($streak-1,$Config.TransientErrorBackoffMs.Count-1)]
            } else {
                $streak=0
                $result = Resolve-NewTabCandidate $Baseline.Ids @(Get-TargetViews $obs $Fingerprint) $seen
                $Diagnostics.SeenCandidateCount=$seen.Count
                if ($result.State -in @('Invalid','Ambiguous')) { $reason=$result.Reason; break }
                if ($result.State -eq 'Unique') {
                    if ($stableId -cne $result.View.Identity) { $stableId=$result.View.Identity; $since=(& $Adapter.Now) }
                    $reason='DetectionTimeout'
                    if (((& $Adapter.Now)-$since) -ge $Config.StableDurationMs -and (& $Adapter.Now) -lt $deadline) {
                        $candidate=$result.View; $reason='ConfirmedCandidate'; break
                    }
                } else { $stableId=$null; $reason=$result.Reason }
                $delay=$Config.PollIntervalMs
            }
            Wait-Poll $Adapter $deadline $delay
        }
        return @{ Reason=$reason; View=$candidate; Seen=$seen }
    } finally { $Diagnostics.DetectionElapsedMs=[int]((& $Adapter.Now)-$start) }
}

function ConvertTo-ComparablePath([string]$Path) {
    # Only trailing separators and case are insignificant. Keep drive and UNC roots intact.
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $root = [IO.Path]::GetPathRoot($Path)
    $trimmed = $Path.TrimEnd([char[]]'\/')
    if ($trimmed.Length -lt $root.Length) { return $root.ToUpperInvariant() }
    return $trimmed.ToUpperInvariant()
}

function Test-PathEqual([string]$Left, [string]$Right) {
    (ConvertTo-ComparablePath $Left) -ceq (ConvertTo-ComparablePath $Right)
}

function Wait-TabNavigation($Adapter, $Fingerprint, $Baseline, $Candidate, $Path, $Config, $Diagnostics) {
    $start=(& $Adapter.Now); $deadline=$start+1000*$Config.NavigationTimeoutSeconds
    $since=$null; $seen=@{}; $seen[$Candidate.Identity]=$Candidate
    while ((& $Adapter.Now) -lt $deadline) {
        if (-not (Test-TargetWindow $Adapter $Fingerprint)) { return 'WindowGone' }
        $obs=& $Adapter.Observe
        Add-ObservationDiagnostic $Diagnostics $obs ((& $Adapter.Now)-$start) 'Navigation'
        if ($obs.GlobalUnavailable) { throw 'ShellUnavailable' }
        if ($obs.IdentitySetReliable) {
            $resolved=Resolve-NewTabCandidate $Baseline.Ids @(Get-TargetViews $obs $Fingerprint) $seen
            if ($resolved.State -ne 'Unique' -or $resolved.View.Identity -cne $Candidate.Identity) { return 'IdentityChanged' }
            if ($resolved.View.PathReadable -and (Test-PathEqual $resolved.View.Path $Path)) {
                if ($null -eq $since) { $since=(& $Adapter.Now) }
                if (((& $Adapter.Now)-$since) -ge $Config.StableDurationMs -and (& $Adapter.Now) -lt $deadline) { return 'Verified' }
            } else { $since=$null }
        } else { $since=$null }
        Wait-Poll $Adapter $deadline $Config.PollIntervalMs
    }
    return 'NavigationTimeout'
}

function Write-RestoreCheckpoint($Run, [string]$Path) {
    $temp = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('.'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        $Run.UpdatedAtUtc=[DateTime]::UtcNow.ToString('o')
        [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $Run -Depth 32), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function New-RestoreItem([int]$GroupIndex, [int]$ItemIndex, $Path) {
    [pscustomobject]@{
        GroupIndex=$GroupIndex; ItemIndex=$ItemIndex; RequestedPath=$Path; Status='NotAttempted'; ReasonCode=''
        WindowCreateAttempted=$false; InvokeAttempted=$false; NavigateAttempted=$false; ElapsedMs=0
        InvokeAttemptedAtUtc=$null; NavigateAttemptedAtUtc=$null
        WindowFingerprint=$null; Diagnostics=$null; Error=$null
    }
}

function Invoke-TabTransaction($Item, $Adapter, $Fingerprint, $Config, [scriptblock]$Checkpoint) {
    $start=& $Adapter.Now
    $Item.WindowFingerprint=$Fingerprint
    $Item.Diagnostics=New-DetectionDiagnostics $Config
    try {
        $baseline=Wait-StableTabBaseline $Adapter $Fingerprint $Config $Item.Diagnostics
        if ($baseline.Reason -ne 'Stable') { $Item.Status='PreconditionFailed'; $Item.ReasonCode=$baseline.Reason; return }
        try { $pattern=& $Adapter.PrepareInvoke $Fingerprint.Hwnd }
        catch { $Item.Status='PreconditionFailed'; $Item.ReasonCode='InvokeControlUnavailable'; $Item.Error=$_.Exception.Message; return }
        if (-not (Test-TargetWindow $Adapter $Fingerprint)) { $Item.Status='PreconditionFailed'; $Item.ReasonCode='WindowGone'; return }
        # Refresh after UIA lookup. A changed baseline must never be silently accepted.
        $obs=& $Adapter.Observe
        Add-ObservationDiagnostic $Item.Diagnostics $obs ((& $Adapter.Now)-$start) 'BeforeInvoke'
        if ($obs.GlobalUnavailable) { throw 'ShellUnavailable' }
        $pre=Resolve-NewTabCandidate $baseline.Ids @(Get-TargetViews $obs $Fingerprint) @{}
        if (-not $obs.IdentitySetReliable -or $pre.State -ne 'Pending' -or
            -not (Test-TargetWindow $Adapter $Fingerprint)) {
            $Item.Status='PreconditionFailed'; $Item.ReasonCode='BaselineChanged'; return
        }
        $Item.InvokeAttempted=$true; $Item.Status='OutcomeUnknown'; $Item.ReasonCode='InvokeAttempted'
        $Item.InvokeAttemptedAtUtc=[DateTime]::UtcNow.ToString('o')
        & $Checkpoint # Must succeed before entering the non-idempotent call.
        $invokeFailed=$false
        try { & $Adapter.Invoke $pattern }
        catch { $invokeFailed=$true; $Item.Error=[pscustomobject]@{ Message=$_.Exception.Message; HResult=$_.Exception.HResult } }
        $result=Wait-NewTabCandidate $Adapter $Fingerprint $baseline $Config $Item.Diagnostics
        if ($invokeFailed) { $Item.ReasonCode='InvokeOutcomeUnknown'; return }
        if ($result.Reason -ne 'ConfirmedCandidate') { $Item.ReasonCode=$result.Reason; return }
        $obs=& $Adapter.Observe
        Add-ObservationDiagnostic $Item.Diagnostics $obs ((& $Adapter.Now)-$start) 'BeforeNavigate'
        if ($obs.GlobalUnavailable) { throw 'ShellUnavailable' }
        $resolved=Resolve-NewTabCandidate $baseline.Ids @(Get-TargetViews $obs $Fingerprint) $result.Seen
        if (-not $obs.IdentitySetReliable -or $resolved.State -ne 'Unique' -or
            -not (Test-TargetWindow $Adapter $Fingerprint)) { $Item.ReasonCode='CandidateRevalidationFailed'; return }
        $Item.NavigateAttempted=$true; $Item.NavigateAttemptedAtUtc=[DateTime]::UtcNow.ToString('o')
        $Item.ReasonCode='NavigateAttempted'; & $Checkpoint
        try { & $Adapter.Navigate $resolved.View $Item.RequestedPath }
        catch { $Item.ReasonCode='NavigationException'; $Item.Error=$_.Exception.Message; return }
        $reason=Wait-TabNavigation $Adapter $Fingerprint $baseline $resolved.View $Item.RequestedPath $Config $Item.Diagnostics
        $Item.ReasonCode=$reason
        if ($reason -eq 'Verified') { $Item.Status='Verified' }
    } finally { $Item.ElapsedMs=[int]((& $Adapter.Now)-$start) }
}

function Wait-NewExplorerWindow($Adapter, $Known, $Path, $Config, $Diagnostics) {
    $start=(& $Adapter.Now); $deadline=$start+12000; $seen=@{}; $since=$null; $chosen=$null
    while ((& $Adapter.Now) -lt $deadline) {
        $obs=& $Adapter.Observe
        Add-ObservationDiagnostic $Diagnostics $obs ((& $Adapter.Now)-$start) 'NewWindow'
        if ($obs.GlobalUnavailable) { throw 'ShellUnavailable' }
        if ($obs.IdentitySetReliable) {
            $matches=@($obs.Views | Where-Object { $_.RootHwnd -notin $Known -and $_.PathReadable -and (Test-PathEqual $_.Path $Path) } |
                Group-Object RootHwnd | ForEach-Object { $_.Group[0] })
            foreach ($view in $matches) { $seen[[string]$view.RootHwnd]=$view }
            if ($seen.Count -gt 1) { return @{ Reason='WindowAmbiguous' } }
            if ($matches.Count -eq 1) {
                if ($null -eq $since) { $since=(& $Adapter.Now); $chosen=$matches[0] }
                if (-not (Test-TargetWindow $Adapter $chosen.Fingerprint)) { return @{ Reason='WindowGone' } }
                if (((& $Adapter.Now)-$since) -ge $Config.StableDurationMs -and (& $Adapter.Now) -lt $deadline) {
                    return @{ Reason='Verified'; View=$matches[0] }
                }
            } else { $since=$null }
        } else { $since=$null }
        Wait-Poll $Adapter $deadline $Config.PollIntervalMs
    }
    return @{ Reason='WindowDetectionTimeout' }
}

function Read-Snapshot([string]$Path) {
    $data=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.Version -ne 1 -or $null -eq $data.Windows) { throw 'Unsupported or invalid snapshot.' }
    foreach ($group in @($data.Windows)) { if ($null -eq $group.Paths) { throw 'Snapshot group has no Paths.' } }
    return $data
}

function Save-Snapshot([string]$Path) {
    $obs=Get-ExplorerObservation
    if (-not $obs.IdentitySetReliable) { throw 'Cannot capture an incomplete Explorer observation.' }
    $tabs=@($obs.Views | Where-Object { $_.PathReadable -and [IO.Directory]::Exists($_.Path) })
    $groups=@($tabs | Group-Object RawHwnd | ForEach-Object { [pscustomobject]@{ Paths=@($_.Group.Path) } })
    $data=[pscustomobject]@{ Version=1; CapturedAt=(Get-Date).ToString('o'); Windows=$groups }
    [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $data -Depth 6),(New-Object Text.UTF8Encoding($false)))
    Write-Host "Saved $($groups.Count) window(s), $($tabs.Count) tab(s): $Path"
}

function New-Run($Items, $Hash, $Source, $ParentRunId) {
    [pscustomobject]@{
        SchemaVersion=1; RunId=[guid]::NewGuid().ToString('N'); ParentRunId=$ParentRunId
        RootRunId=$null; RootReportPath=$null
        StartedAtUtc=[DateTime]::UtcNow.ToString('o'); UpdatedAtUtc=''; ToolVersion=$script:ResumeExplorerVersion
        SourceSnapshotHash=$Hash; SourceSnapshot=$Source; OSVersion=[Environment]::OSVersion.VersionString
        PowerShellVersion=$PSVersionTable.PSVersion.ToString(); State='Running'; Error=$null; Items=@($Items)
    }
}

function Initialize-RunPath($Run, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path=Join-Path (Join-Path $env:LOCALAPPDATA 'ResumeExplorer\Runs') ($Run.RunId+'.json')
    }
    $Path=[IO.Path]::GetFullPath($Path)
    if (-not $Run.RootRunId) { $Run.RootRunId=$Run.RunId; $Run.RootReportPath=$Path }
    $directory=[IO.Path]::GetDirectoryName($Path)
    [void][IO.Directory]::CreateDirectory($directory)
    # Reserve exclusively: reports must not overwrite an existing run.
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $stream.Dispose()
    Write-RestoreCheckpoint $Run $Path
    return $Path
}

function Write-RunSummary($Run, $Path) {
    Write-Host "Report: $Path ($($Run.State))"
    foreach ($group in @($Run.Items | Group-Object Status)) { Write-Host "  $($group.Name): $($group.Count)" }
}

function Invoke-RestoreGroups($Run, $Adapter, $Config, $Checkpoint, $ExistingFingerprint) {
    foreach ($group in @($Run.Items | Group-Object GroupIndex)) {
        $eligible=@()
        foreach ($item in $group.Group) {
            if ($item.RequestedPath -isnot [string] -or [string]::IsNullOrWhiteSpace($item.RequestedPath) -or
                $item.RequestedPath.Contains('"') -or -not (& $Adapter.PathExists $item.RequestedPath)) {
                $item.Status='SkippedInvalidPath'; $item.ReasonCode='InvalidPath'
            } else { $eligible+= $item }
        }
        & $Checkpoint
        if (-not $eligible.Count) { continue }
        $fp=$ExistingFingerprint; $offset=0
        if ($null -eq $fp) {
            $first=$eligible[0]; $start=& $Adapter.Now
            $obs=& $Adapter.Observe
            if ($obs.GlobalUnavailable) { throw 'ShellUnavailable' }
            if (-not $obs.IdentitySetReliable) { $first.Status='PreconditionFailed'; $first.ReasonCode='ObservationIncomplete'; & $Checkpoint; continue }
            $known=@($obs.Views.RootHwnd | Sort-Object -Unique)
            $first.Diagnostics=New-DetectionDiagnostics $Config
            $first.Status='OutcomeUnknown'; $first.WindowCreateAttempted=$true; $first.ReasonCode='WindowCreateAttempted'; & $Checkpoint
            $openFailed=$false
            try { & $Adapter.OpenWindow $first.RequestedPath }
            catch { $openFailed=$true; $first.Error=$_.Exception.Message }
            $result=Wait-NewExplorerWindow $Adapter $known $first.RequestedPath $Config $first.Diagnostics
            $first.ElapsedMs=[int]((& $Adapter.Now)-$start)
            if ($openFailed) { $first.ReasonCode='WindowCreateOutcomeUnknown'; & $Checkpoint; continue }
            $first.ReasonCode=$result.Reason
            if ($result.Reason -ne 'Verified') { & $Checkpoint; continue }
            $fp=$result.View.Fingerprint; $first.WindowFingerprint=$fp; $first.Status='Verified'; $offset=1; & $Checkpoint
        }
        foreach ($item in @($eligible | Select-Object -Skip $offset)) {
            Invoke-TabTransaction $item $Adapter $fp $Config $Checkpoint
            & $Checkpoint
            if ($item.Status -ne 'Verified') { break }
        }
        & $Checkpoint
    }
}

function Complete-Run($Run, $Path, $Adapter, $Config, $Fingerprint) {
    $writeCheckpointFunction=${function:Write-RestoreCheckpoint}
    $checkpoint={ & $writeCheckpointFunction $Run $Path }.GetNewClosure()
    try {
        Invoke-RestoreGroups $Run $Adapter $Config $checkpoint $Fingerprint
        $Run.State='Completed'
    } catch {
        $Run.State='Aborted'; $Run.Error=$_.Exception.Message
        throw
    } finally {
        try { Write-RestoreCheckpoint $Run $Path }
        catch { Write-Warning "Checkpoint failed. No further Explorer actions will run. $($_.Exception.Message)"; Write-Host (ConvertTo-Json -InputObject $Run -Depth 32); throw }
        finally { Write-RunSummary $Run $Path }
    }
}

function Start-RestoreRun([string]$Snapshot, [string]$ReportPath, $Config) {
    Assert-RestoreConfig $Config
    $data=Read-Snapshot $Snapshot; $items=@(); $g=0
    foreach ($group in @($data.Windows)) {
        $g++; $i=0
        foreach ($path in @($group.Paths)) { $i++; $items+=New-RestoreItem $g $i $path }
    }
    $hash=(Get-FileHash -LiteralPath $Snapshot -Algorithm SHA256).Hash
    $run=New-Run $items $hash ([IO.Path]::GetFullPath($Snapshot)) $null
    $destination=Initialize-RunPath $run $ReportPath
    Complete-Run $run $destination (New-ExplorerAdapter) $Config $null
}

function Read-RunReport([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'ReportPath is required.' }
    $run=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($run.SchemaVersion -ne 1 -or -not $run.RunId -or $null -eq $run.Items) { throw 'Invalid run report.' }
    $keys=@{}
    foreach ($item in @($run.Items)) {
        $key="$($item.GroupIndex):$($item.ItemIndex)"
        if ($item.GroupIndex -lt 1 -or $item.ItemIndex -lt 1 -or $keys.ContainsKey($key) -or
            $item.Status -notin @('Verified','NotAttempted','PreconditionFailed','OutcomeUnknown','SkippedInvalidPath')) { throw 'Invalid report item.' }
        $keys[$key]=$true
    }
    return $run
}

function Get-CurrentExplorerTargets($Adapter) {
    $obs=& $Adapter.Observe
    if (-not $obs.IdentitySetReliable) { throw 'Cannot reliably enumerate current Explorer targets.' }
    @($obs.Views | Group-Object RawHwnd | ForEach-Object { $_.Group[0].Fingerprint })
}

function Show-RetryPreview([string]$ReportPath) {
    $source=Read-RunReport $ReportPath
    $adapter=New-ExplorerAdapter
    $targets=@(Get-CurrentExplorerTargets $adapter)
    $previewPath=[IO.Path]::GetFullPath($ReportPath)+'.retry-preview.json'
    $preview=[pscustomobject]@{ RunId=$source.RunId; ReportHash=(Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash
        PreviewedAtUtc=[DateTime]::UtcNow.ToString('o'); Targets=$targets }
    [IO.File]::WriteAllText($previewPath,(ConvertTo-Json -InputObject $preview -Depth 8),(New-Object Text.UTF8Encoding($false)))
    $source.Items | Select-Object GroupIndex,ItemIndex,RequestedPath,Status,ReasonCode | Format-Table -AutoSize | Out-Host
    $targets | Format-Table Hwnd,RootHwnd,PID,ProcessStartedAtUtc,SessionId -AutoSize | Out-Host
    Write-Host "Target fingerprint preview saved: $previewPath"
}

function Select-RetryItems($Source, [int]$GroupIndex, [int[]]$ItemIndexes, [bool]$IncludeUncertain, $ChildItems) {
    if ($GroupIndex -lt 1 -or -not $ItemIndexes.Count -or @($ItemIndexes | Select-Object -Unique).Count -ne $ItemIndexes.Count) {
        throw 'Specify a GroupIndex and distinct ItemIndexes.'
    }
    $selected=@()
    foreach ($index in $ItemIndexes) {
        $match=@($Source.Items | Where-Object { $_.GroupIndex -eq $GroupIndex -and $_.ItemIndex -eq $index })
        if ($match.Count -ne 1) { throw "Unknown item: $index" }
        $item=$match[0]
        if ($item.Status -eq 'Verified') { throw "Item $index is already Verified." }
        $prior=@($ChildItems | Where-Object { $_.GroupIndex -eq $GroupIndex -and $_.ItemIndex -eq $index })
        if (@($prior | Where-Object { $_.Status -eq 'Verified' }).Count) { throw "Item $index was already completed by a child run." }
        $uncertain=$item.Status -eq 'OutcomeUnknown' -or $item.InvokeAttempted -or $item.NavigateAttempted -or $item.WindowCreateAttempted -or
            @($prior | Where-Object { $_.InvokeAttempted -or $_.NavigateAttempted -or $_.WindowCreateAttempted -or $_.Status -eq 'OutcomeUnknown' }).Count -gt 0
        if ($uncertain -and -not $IncludeUncertain) { throw "Item $index requires IncludeUncertain." }
        $selected+=New-RestoreItem $GroupIndex $index $item.RequestedPath
    }
    return $selected
}

function Get-RetryDescendantItems($Source, [string]$ReportPath) {
    if ($Source.RootReportPath) { $ReportPath=$Source.RootReportPath }
    $directory=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath))) 'RetryRuns'
    if (-not [IO.Directory]::Exists($directory)) { return @() }
    $reports=@(Get-ChildItem -LiteralPath $directory -Filter '*.json' -Recurse -File |
        Where-Object { $_.Name -notlike '*.retry-preview.json' } | ForEach-Object { Read-RunReport $_.FullName })
    $parents=@($Source.RunId); $items=@()
    if ($Source.RootRunId) {
        foreach ($report in $reports) {
            if ($report.RootRunId -eq $Source.RootRunId) { $items+=@($report.Items) }
        }
        return $items
    }
    do {
        $next=@($reports | Where-Object { $_.ParentRunId -in $parents })
        $parents=@($next.RunId)
        foreach ($report in $next) { $items+=@($report.Items) }
        $reports=@($reports | Where-Object { $_.RunId -notin $parents })
    } while ($parents.Count)
    return $items
}

function Start-RetryRun([string]$ReportPath, [int]$GroupIndex, [long]$TargetHwnd, [int[]]$ItemIndexes, [switch]$IncludeUncertain, $Config) {
    Assert-RestoreConfig $Config
    if ($TargetHwnd -le 0) { throw 'TargetHwnd is required.' }
    $ReportPath=[IO.Path]::GetFullPath($ReportPath)
    $source=Read-RunReport $ReportPath
    $lockPath=$ReportPath+'.retry.lock'
    if ($source.RootReportPath) { $lockPath=$source.RootReportPath+'.retry.lock' }
    # Serialize all retries in this run family, including retries of a child report.
    $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $source=Read-RunReport $ReportPath
        $children=@(Get-RetryDescendantItems $source $ReportPath)
        $selected=@(Select-RetryItems $source $GroupIndex $ItemIndexes ([bool]$IncludeUncertain) $children)
        $preview=Get-Content -LiteralPath ($ReportPath+'.retry-preview.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($preview.RunId -ne $source.RunId -or $preview.ReportHash -ne (Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash) { throw 'Report changed; run PreviewRetry again.' }
        $expected=@($preview.Targets | Where-Object { $_.Hwnd -eq $TargetHwnd })
        if ($expected.Count -ne 1) { throw 'Target was not previewed. Run PreviewRetry again.' }
        $adapter=New-ExplorerAdapter
        $current=& $adapter.Fingerprint $TargetHwnd
        if (-not (Test-FingerprintEqual $expected[0] $current)) { throw 'Stale retry target. Run PreviewRetry again.' }
        $run=New-Run $selected $source.SourceSnapshotHash $source.SourceSnapshot $source.RunId
        $run.RootRunId=$source.RootRunId; $run.RootReportPath=$source.RootReportPath
        $destination=Join-Path (Join-Path ([IO.Path]::GetDirectoryName($ReportPath)) 'RetryRuns') ($run.RunId+'.json')
        $destination=Initialize-RunPath $run $destination
        Complete-Run $run $destination $adapter $Config $current
    } finally { $lock.Dispose() }
}
