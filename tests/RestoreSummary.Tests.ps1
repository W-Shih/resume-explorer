# Offline summary tests; never invoke Shell, UIA, PreviewRetry or a real Restore.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'resume-explorer.core.ps1')
$script:passed=0
function Assert($Condition, $Message='Assertion failed') { if (-not $Condition) { throw $Message } }
function Test($Name, [scriptblock]$Body) {
    & $Body; $script:passed++; Write-Host "PASS $Name"
}
function New-SummaryRun($Statuses, [string]$State='Completed') {
    $items=@(); $index=0
    foreach ($status in $Statuses) {
        $index++; $item=New-RestoreItem 2 $index 'C:\repeated path'
        $item.Status=$status; $items+=$item
    }
    $run=New-Run $items 'hash' 'snapshot' $null; $run.State=$State; return $run
}
function Capture-Summary($Run, [string]$Path='C:\runs\test.json') {
    $records=@(Write-RunSummary $Run $Path 3>&1 6>&1)
    [pscustomobject]@{
        Text=(@($records | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { $_.MessageData.ToString() }) -join "`n")
        Warnings=@($records | Where-Object { $_ -is [Management.Automation.WarningRecord] })
        Other=@($records | Where-Object { $_ -isnot [Management.Automation.WarningRecord] -and $_ -isnot [Management.Automation.InformationRecord] })
    }
}
Test 'S01 complete 18/18 emits one Verified count, no warning or retry' {
    $run=New-SummaryRun (@('Verified')*18); $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert ($s.Verification -eq 'Complete' -and $s.Total -eq 18 -and $s.NotVerified -eq 0)
    Assert ($o.Text.StartsWith('Report: C:\runs\test.json (Completed)'))
    Assert ($o.Text.Contains('All 18 items verified.') -and $o.Warnings.Count -eq 0)
    Assert (-not $o.Text.Contains('Unverified items:') -and -not $o.Text.Contains('PreviewRetry'))
    Assert ([regex]::Matches($o.Text,'(?m)^  Verified:').Count -eq 1)
    Assert ($o.Other.Count -eq 0) 'Summary must not leak objects to success output'
}
Test 'S02 partial 15/18 reports every unverified index, path and reason' {
    $run=New-SummaryRun ((@('Verified')*15)+@('OutcomeUnknown','NotAttempted','SkippedInvalidPath'))
    $run.Items[15].ReasonCode='AmbiguousCandidates'; $run.Items[17].ReasonCode='InvalidPath'
    $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert ($s.Verification -eq 'Partial' -and $s.Verified -eq 15 -and $s.NotVerified -eq 3)
    foreach ($text in @('Group 2:','Tab 16 | OutcomeUnknown | AmbiguousCandidates','Tab 17 | NotAttempted','Tab 18 | SkippedInvalidPath | InvalidPath','Path: C:\repeated path')) { Assert ($o.Text.Contains($text)) $text }
    Assert ($o.Warnings.Count -eq 1 -and $o.Warnings[0].Message -eq '3 of 18 items were not verified.')
    Assert ($o.Text.IndexOf('  OutcomeUnknown:') -lt $o.Text.IndexOf('  NotAttempted:'))
}
Test 'S03 zero verified is Partial rather than success' {
    $run=New-SummaryRun @('NotAttempted'); $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert ($s.Verification -eq 'Partial' -and $s.Verified -eq 0 -and $s.Total -eq 1)
    Assert (-not $o.Text.Contains('All 1 items verified.'))
}
Test 'S04 empty run has no meaningless retry command' {
    $run=New-SummaryRun @(); $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert ($s.Verification -eq 'Empty' -and $s.Total -eq 0 -and $s.NotVerified -eq 0)
    Assert ($o.Text.Contains('No restore items were found.') -and -not $o.Text.Contains('PreviewRetry') -and $o.Warnings.Count -eq 0)
    $run.Items=$null; Assert ((Get-RunSummary $run).Total -eq 0)
}
Test 'S05 aborted run renders Interrupted and leaves the original error intact' {
    $run=New-SummaryRun @('Verified','NotAttempted') 'Aborted'; $o=Capture-Summary $run
    Assert ($o.Text.Contains('Verification: Interrupted') -and $o.Text.Contains('Tab 2 | NotAttempted'))
    Assert ($o.Warnings.Count -eq 2)
    $expected=New-Object InvalidOperationException 'original restore exception'
    function Invoke-RestoreGroups { throw $expected }
    function Write-RestoreCheckpoint { }
    $caught=$null
    try { Complete-Run $run 'C:\runs\test.json' @{} @{} $null 3>$null 6>$null } catch { $caught=$_.Exception }
    Assert ([object]::ReferenceEquals($caught,$expected)) 'Summary replaced the original exception'
    Assert ($run.State -eq 'Aborted')
}
Test 'S06 aborted but all verified must not print a success conclusion' {
    $run=New-SummaryRun @('Verified') 'Aborted'; $o=Capture-Summary $run
    Assert ($o.Text.Contains('Verification: Interrupted') -and -not $o.Text.Contains('All 1 items verified.'))
    Assert ($o.Warnings.Count -eq 1 -and -not $o.Text.Contains('PreviewRetry'))
}
Test 'S07 unknown outcome is not labelled failed and cannot invoke any retry' {
    function New-ExplorerAdapter { throw 'Unexpected Explorer access' }
    function Show-RetryPreview { throw 'Unexpected preview execution' }
    function Start-RetryRun { throw 'Unexpected retry execution' }
    $o=Capture-Summary (New-SummaryRun @('OutcomeUnknown'))
    Assert ($o.Warnings[0].Message.Contains('not verified') -and -not $o.Warnings[0].Message.Contains('failed'))
    Assert ($o.Text.Contains('Review retry options:'))
}
Test 'S08 all nonverified statuses counted in fixed priority, optional reasons omitted' {
    $run=New-SummaryRun @('SkippedInvalidPath','NotAttempted','PreconditionFailed','OutcomeUnknown')
    $run.Items[0].ReasonCode='InvalidPath'; $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert ($s.NotVerified -eq 4 -and ($s.StatusCounts.Keys -join ',') -eq 'OutcomeUnknown,PreconditionFailed,NotAttempted,SkippedInvalidPath')
    Assert ($o.Text.Contains('Tab 2 | NotAttempted') -and -not $o.Text.Contains('Tab 2 | NotAttempted |'))
}
Test 'S09 repeated paths retain separate original requests and input remains unchanged' {
    $run=New-SummaryRun @('NotAttempted','OutcomeUnknown','NotAttempted'); $run.Items[2].GroupIndex=5
    $before=ConvertTo-Json -InputObject $run -Depth 32; $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert ($s.Total -eq 3 -and [regex]::Matches($o.Text,[regex]::Escape('Path: C:\repeated path')).Count -eq 3)
    Assert ((ConvertTo-Json -InputObject $run -Depth 32) -ceq $before)
}
Test 'S10 original numeric group/item order is preserved without renumbering' {
    $run=New-SummaryRun @('NotAttempted','NotAttempted','NotAttempted')
    $run.Items[0].GroupIndex=10; $run.Items[0].ItemIndex=20
    $run.Items[1].ItemIndex=12; $run.Items[2].ItemIndex=3
    $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert (($s.UnverifiedItems.ItemIndex -join ',') -eq '3,12,20')
    Assert ($o.Text.IndexOf('Group 2:') -lt $o.Text.IndexOf('Group 10:'))
    Assert ($o.Text.IndexOf('Tab 3 |') -lt $o.Text.IndexOf('Tab 12 |'))
}
Test 'S11 retry command quotes absolute script and report paths safely' {
    $path="C:\runs with spaces\O'Brien.json"; $o=Capture-Summary (New-SummaryRun @('NotAttempted')) $path
    $command=@($o.Text -split "`n" | Where-Object { $_.TrimStart().StartsWith('& ') })[0]
    $tokens=$null; $errors=$null; $ast=[Management.Automation.Language.Parser]::ParseInput($command,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0)
    $elements=$ast.EndBlock.Statements[0].PipelineElements[0].CommandElements
    Assert ($elements[0].Value -eq (Join-Path (Split-Path $PSScriptRoot -Parent) 'resume-explorer.ps1'))
    Assert ($elements[4].Value -ceq $path)
    Assert ($command.Contains("O''Brien.json"))
}
Test 'S12 missing fields and future statuses count as unverified' {
    $run=New-SummaryRun @('FutureStatus',$null,' '); $run.Items+= [pscustomobject]@{ GroupIndex=3; ItemIndex=99 }
    $s=Get-RunSummary $run; $o=Capture-Summary $run
    Assert ($s.NotVerified -eq 4 -and $s.StatusCounts.Unknown -eq 3 -and $s.StatusCounts.FutureStatus -eq 1)
    Assert ($o.Text.Contains('Tab 99 | Unknown') -and $o.Text.Contains('FutureStatus: 1'))
    $run.State='FutureRunState'; Assert ((Get-RunSummary $run).Verification -eq 'Partial')
}
Test 'S13 external controls are visible escapes, not forged console lines' {
    $run=New-SummaryRun @('NotAttempted'); $run.Items[0].RequestedPath="C:\one`r`nFORGED`t$([char]27)$([char]0)$([char]0x2028)"
    $run.Items[0].Status="Future`nStatus"; $run.Items[0].ReasonCode="Reason`rCode"
    $before=$run.Items[0].RequestedPath; $o=Capture-Summary $run
    Assert ($o.Text.Contains('C:\one\r\nFORGED\t\u001B\u0000\u2028'))
    Assert ($o.Text.Contains('Future\nStatus') -and $o.Text.Contains('Reason\rCode'))
    Assert (-not $o.Text.Contains("`nFORGED") -and $run.Items[0].RequestedPath -ceq $before)
}
Test 'S14 child run summary describes only its selected items and report' {
    $run=New-SummaryRun @('Verified','NotAttempted'); $run.ParentRunId='parent'
    $o=Capture-Summary $run 'C:\runs\RetryRuns\child.json'
    Assert ($o.Text.StartsWith('Report: C:\runs\RetryRuns\child.json (Completed)') -and $o.Text.Contains('  Total: 2'))
}
Test 'S15 Complete-Run saves the same schema and summary never changes report bytes' {
    $directory=Join-Path $env:TEMP ('resume-summary-tests-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try {
        $run=New-SummaryRun @('NotAttempted'); $run.State='Running'
        $path=Initialize-RunPath $run (Join-Path $directory 'run.json')
        $calls=New-Object System.Collections.ArrayList
        function Invoke-RestoreGroups($Run,$Adapter,$Config,$Checkpoint,$ExistingFingerprint) {
            & $Checkpoint; [void]$calls.Add('checkpoint-before'); $Run.Items[0].Status='Verified'; & $Checkpoint
        }
        Complete-Run $run $path @{} @{} $null 3>$null 6>$null
        Assert ($calls.Count -eq 1 -and (Read-RunReport $path).State -eq 'Completed')
        $before=(Get-FileHash -LiteralPath $path).Hash; $json=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $originalKeys=@($json.PSObject.Properties.Name) -join ','
        $null=Capture-Summary $run $path
        Assert ((Get-FileHash -LiteralPath $path).Hash -eq $before -and $json.SchemaVersion -eq 1)
        Assert ($originalKeys -ceq (@($run.PSObject.Properties.Name) -join ','))
    } finally { Get-ChildItem -LiteralPath $directory -File | Remove-Item; [IO.Directory]::Delete($directory) }
}
Test 'S16 failed final checkpoint retains warning, memory JSON and original throw' {
    $run=New-SummaryRun @('NotAttempted'); $expected=New-Object IO.IOException 'disk unavailable'
    function Invoke-RestoreGroups { }
    function Write-RestoreCheckpoint { throw $expected }
    $records=New-Object System.Collections.ArrayList; $caught=$null
    try { Complete-Run $run 'C:\runs\stale.json' @{} @{} $null 3>&1 6>&1 | ForEach-Object { [void]$records.Add($_) } }
    catch { $caught=$_.Exception }
    Assert ([object]::ReferenceEquals($caught,$expected))
    Assert (@($records | Where-Object { $_ -is [Management.Automation.WarningRecord] -and $_.Message.Contains('Checkpoint failed') }).Count -eq 1)
    $text=($records | ForEach-Object { $_.ToString() }) -join "`n"
    # Task-4: JSON whitespace differs across PS5.1/7; validate the fallback's
    # semantics, not formatter spacing. Write-Host MessageData may be a
    # HostInformationMessage rather than a string, so use its text representation.
    $assertFallback = {
        param($informationRecords, $expectedRun)
        $jsonRecords=@($informationRecords | Where-Object {
            $_ -is [Management.Automation.InformationRecord] -and
            $null -ne $_.MessageData -and $_.MessageData.ToString().TrimStart().StartsWith('{')
        })
        Assert ($jsonRecords.Count -eq 1) 'Expected exactly one in-memory fallback JSON record'
        $memoryRun=$jsonRecords[0].MessageData.ToString() | ConvertFrom-Json -ErrorAction Stop
        Assert ($memoryRun.SchemaVersion -eq 1) 'Fallback schema mismatch'
        Assert ($memoryRun.RunId -ceq $expectedRun.RunId) 'Fallback run identity mismatch'
        Assert ($memoryRun.State -ceq $expectedRun.State) 'Fallback state mismatch'
        Assert (@($memoryRun.Items).Count -eq @($expectedRun.Items).Count) 'Fallback item count mismatch'
        Assert ($memoryRun.Items[0].GroupIndex -eq $expectedRun.Items[0].GroupIndex) 'Fallback group mismatch'
        Assert ($memoryRun.Items[0].ItemIndex -eq $expectedRun.Items[0].ItemIndex) 'Fallback item index mismatch'
        Assert ($memoryRun.Items[0].Status -ceq 'NotAttempted') 'Fallback item status mismatch'
        Assert ($memoryRun.Items[0].RequestedPath -ceq $expectedRun.Items[0].RequestedPath) 'Fallback path mismatch'
    }
    & $assertFallback $records $run
    Assert ($text.Contains('Report: C:\runs\stale.json'))
    Assert (-not $text.Contains('Report saved') -and -not $text.Contains('Report updated'))

    # Independent negative fixtures exercise the same assertion without calling
    # Complete-Run again or sharing mocks with any other test.
    $validJson=ConvertTo-Json -InputObject $run -Depth 32
    $invalidPayloads=@('{ invalid JSON', '{}')
    foreach ($field in @('SchemaVersion','RunId','State','Items','GroupIndex','ItemIndex','Status','RequestedPath')) {
        $wrong=$validJson | ConvertFrom-Json
        switch ($field) {
            'SchemaVersion' { $wrong.SchemaVersion=2 }
            'RunId' { $wrong.RunId='different-run' }
            'State' { $wrong.State='Aborted' }
            'Items' { $wrong.Items=@() }
            'GroupIndex' { $wrong.Items[0].GroupIndex=99 }
            'ItemIndex' { $wrong.Items[0].ItemIndex=99 }
            'Status' { $wrong.Items[0].Status='Verified' }
            'RequestedPath' { $wrong.Items[0].RequestedPath='C:\wrong' }
        }
        $invalidPayloads+=ConvertTo-Json -InputObject $wrong -Depth 32
    }
    $negativeCases=@(@{ Name='missing'; Records=@() })
    foreach ($payload in $invalidPayloads) {
        $record=[Management.Automation.InformationRecord]::new($payload,'S16-negative-fixture')
        $negativeCases+=@{ Name='invalid or mismatched payload'; Records=@($record) }
    }
    $duplicate=[Management.Automation.InformationRecord]::new($validJson,'S16-negative-fixture')
    $negativeCases+=@{ Name='duplicate JSON'; Records=@($duplicate,$duplicate) }
    foreach ($case in $negativeCases) {
        $rejected=$false
        try { & $assertFallback $case.Records $run } catch { $rejected=$true }
        Assert $rejected ("Fallback validation accepted " + $case.Name)
    }
}
Test 'S17 WarningPreference Stop does not terminate summary or mask restore exception' {
    $WarningPreference='Stop'
    $run=New-SummaryRun @('NotAttempted'); $o=Capture-Summary $run
    Assert ($o.Warnings.Count -eq 1)
    $expected=New-Object InvalidOperationException 'original error under warning stop'
    function Invoke-RestoreGroups { throw $expected }
    function Write-RestoreCheckpoint { }
    $caught=$null
    try { Complete-Run $run 'C:\runs\test.json' @{} @{} $null 3>$null 6>$null } catch { $caught=$_.Exception }
    Assert ([object]::ReferenceEquals($caught,$expected))
}
Write-Host "$script:passed restore summary tests passed. No live Explorer actions performed."
