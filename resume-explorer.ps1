# ExplorerTabs v1.4 - no prompts, no SendKeys, tab-group restore via UI Automation + Shell COM.
# Experimental on Windows 11 23H2. Restore ONLY adds windows/tabs; never closes them.
# No network, registry edits, clipboard modifications, execution-policy changes or process termination.
[CmdletBinding()]
param(
    [ValidateSet('Capture','Preview','Restore')]
    [string]$Action = 'Preview',
    [string]$Snapshot = (Join-Path $env:TEMP 'ExplorerTabs-snapshot.json')
)
$ErrorActionPreference = 'Stop'

function Get-TabIdentity($tab) {
    $ptr = [System.Runtime.InteropServices.Marshal]::GetIUnknownForObject($tab)
    try { return $ptr.ToInt64().ToString('X') }
    finally { [void][System.Runtime.InteropServices.Marshal]::Release($ptr) }
}

function Get-ExplorerTabViews {
    $shell = New-Object -ComObject Shell.Application
    $result = @()
    foreach ($w in @($shell.Windows())) {
        try {
            if ([System.IO.Path]::GetFileName([string]$w.FullName) -ine 'explorer.exe') { continue }
            $hwnd = [long]$w.HWND
            if ($hwnd -le 0) { continue }
            $path = ''
            try { $path = [string]$w.Document.Folder.Self.Path } catch {}
            $result += [pscustomobject]@{ HWND = $hwnd; Path = $path; Identity = (Get-TabIdentity $w); ComObject = $w }
        } catch {}
    }
    return $result
}

function Save-Snapshot {
    $tabs = @(Get-ExplorerTabViews | Where-Object { [IO.Directory]::Exists($_.Path) })
    $groups = @()
    foreach ($g in ($tabs | Group-Object HWND)) {
        $groups += [pscustomobject]@{ Paths = @($g.Group | ForEach-Object { $_.Path }) }
    }
    $data = [pscustomobject]@{ Version = 1; CapturedAt = (Get-Date).ToString('o'); Windows = @($groups) }
    [IO.File]::WriteAllText($Snapshot, (ConvertTo-Json -InputObject $data -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Saved $($groups.Count) window(s), $($tabs.Count) tab(s): $Snapshot"
    foreach ($g in $groups) { Write-Host ('  Window: ' + ($g.Paths -join ' | ')) }
}

function Read-Snapshot {
    if (-not (Test-Path -LiteralPath $Snapshot)) { throw "Snapshot not found: $Snapshot" }
    $data = Get-Content -LiteralPath $Snapshot -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.Version -ne 1) { throw 'Unsupported snapshot version.' }
    return $data
}

function Wait-NewExplorerWindow([string]$path, [long[]]$known) {
    $limit = (Get-Date).AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 250
        $matches = @(Get-ExplorerTabViews | Where-Object { $_.HWND -notin $known -and $_.Path -ieq $path })
        if ($matches.Count -gt 0) { return [long]$matches[0].HWND }
    } while ((Get-Date) -lt $limit)
    return 0L
}

function Add-ExplorerTab([long]$hwnd) {
    # UI Automation InvokePattern on Explorer's own new-tab button.
    # No foreground-window selection or synthetic keyboard input.
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    if (-not ('ExplorerTabsUI' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ExplorerTabsUI {
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);
}
'@
    }
    $topHwnd = [ExplorerTabsUI]::GetAncestor([IntPtr]::new($hwnd), 2) # GA_ROOT
    if ($topHwnd -eq [IntPtr]::Zero) { $topHwnd = [IntPtr]::new($hwnd) }
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($topHwnd)
    if ($null -eq $root) { throw "UI Automation cannot access Explorer HWND $hwnd" }
    $prop = [System.Windows.Automation.AutomationElement]::AutomationIdProperty
    $condition = New-Object System.Windows.Automation.PropertyCondition($prop, 'AddButton')
    $button = $root.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $condition)
    if ($null -eq $button) {
        # ShellTabWindowClass may be a child: locate AddButton in its parent top-level window.
        throw "Explorer AddButton not found under HWND $hwnd. No tab was added."
    }
    $pattern = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    if ($null -eq $pattern) { throw 'Explorer AddButton has no InvokePattern.' }
    $pattern.Invoke()
}

function Wait-NewTab([long]$hwnd, [string[]]$previousIds) {
    $limit = (Get-Date).AddSeconds(7)
    do {
        Start-Sleep -Milliseconds 200
        $views = @(Get-ExplorerTabViews | Where-Object { $_.HWND -eq $hwnd -and $_.Identity -notin $previousIds })
        if ($views.Count -eq 1) { return $views[0] }
        if ($views.Count -gt 1) { throw 'Multiple new tabs detected; cannot safely choose one.' }
    } while ((Get-Date) -lt $limit)
    return $null
}

function Restore-Snapshot {
    $data = Read-Snapshot
    $groupIndex = 0
    foreach ($group in @($data.Windows)) {
        $groupIndex++
        $paths = @($group.Paths | Where-Object { $_ -is [string] -and [IO.Directory]::Exists([string]$_) })
        if ($paths.Count -eq 0) { continue }
        $known = @(Get-ExplorerTabViews | Select-Object -ExpandProperty HWND -Unique)
        Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList ('"' + ($paths[0] -replace '"','') + '"')
        $hwnd = Wait-NewExplorerWindow -path ([string]$paths[0]) -known $known
        if ($hwnd -eq 0) {
            Write-Warning "Group ${groupIndex}: no NEW Explorer window detected; skipping additional tabs."
            continue
        }
        Write-Host "Group $groupIndex, HWND $hwnd : $($paths[0])"
        foreach ($path in @($paths | Select-Object -Skip 1)) {
            try {
                $before = @(Get-ExplorerTabViews | Where-Object { $_.HWND -eq $hwnd } | ForEach-Object { $_.Identity })
                Add-ExplorerTab -hwnd $hwnd
                $newTab = Wait-NewTab -hwnd $hwnd -previousIds $before
                if ($null -eq $newTab) { throw 'A new tab was not exposed via Shell.Application in time.' }
                $newTab.ComObject.Navigate2([string]$path)
                Write-Host "  Requested new tab: $path"
                Start-Sleep -Milliseconds 350
                $found = @(Get-ExplorerTabViews | Where-Object { $_.HWND -eq $hwnd -and $_.Path -ieq [string]$path })
                if ($found.Count -eq 0) { Write-Warning "  Navigation was requested but not verified: $path" }
            } catch {
                Write-Warning "Group ${groupIndex}: $($_.Exception.Message) Remaining tabs in this group skipped."
                break
            }
        }
    }
    Write-Host 'Restore attempted. Inspect resulting tabs before considering a restart workflow.'
}

switch ($Action) {
    'Capture' { Save-Snapshot }
    'Preview' {
        $data = Read-Snapshot
        $n = 0
        foreach ($g in @($data.Windows)) {
            $n++
            Write-Host "Window group $n :"
            foreach ($p in @($g.Paths)) { Write-Host "  [$([IO.Directory]::Exists([string]$p))] $p" }
        }
    }
    'Restore' { Restore-Snapshot }
}
