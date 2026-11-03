# Task-5 — PowerShell 7 Explorer smoke harness

For the guided single-launch workflow in a test VM, double-click **`Run-ExplorerSmoke.cmd`** or run `pwsh -NoProfile -Sta -File .\tests\Integration\Start-ExplorerSmoke.ps1 -Run`. See [one-click instructions](ONE-CLICK.md). This automates session evidence, offline checks, verified fixture bootstrap and both cases; actual visual review and manual E01 window closure remain required. The manual workflow below is preserved for diagnosis. The user's completed one-click VM run now supplies the minimal live acceptance; see [evidence and limits](TASK5-VM-ACCEPTANCE.md).

**Task-5 is Closed on user-provided Windows 11 VM acceptance (2026-11-02): E01/E02 Passed, overall exit 0.** Initial development had no isolated desktop and live cases were NotRun; the later user run supersedes that status. Exact VM build/PS minor and raw artifacts have not been independently re-audited by the agent. This is not universal build compatibility or agent-run GUI proof. The execution sandbox is not GUI isolation; do not rerun on a working desktop/VDI.

This harness does not modify the production CLI or install dependencies. It uses a manual-fixture workflow, real public CLI subprocesses for live cases, and a separate Shell COM/Win32/UIA observer. Offline synthetic orchestration tests are tests of the harness, not evidence of Windows GUI success.

## Safe defaults and exit codes

```powershell
# Safe anywhere: no COM observation, UIA search, fixture creation or CLI dispatch.
pwsh -NoProfile -Sta -File .\tests\Integration\Invoke-ExplorerSmoke.ps1

# Offline safety/assertion tests; no Explorer actions.
pwsh -NoProfile -NonInteractive -File .\tests\ExplorerSmoke.Tests.ps1
```

The default returns JSON with `NotRun / NotAuthorized`, both cases `NotRun`, and exit **2**. Dot-sourcing either harness file only defines functions. Discovery/CI should run `ExplorerSmoke.Tests.ps1`, not enable GUI flags.

| Exit | Status |
| --- | --- |
| 0 | Passed, only after observer checks and explicit operator visual review |
| 1 | Failed after at least one actual CLI command was attempted |
| 2 | NotRun / Ready / Prepared / AwaitingVisualReview; never E2E success |
| 3 | Blocked by runtime, session, scope, ownership, replay or evidence checks |

Preflight with valid isolation evidence is read-only. Prepare creates a unique `%TEMP%\ResumeExplorer-E2E-<GUID>` and fixture folders, but **never creates Explorer windows**. Run requires `-AllowExplorerUiChanges`. Confirm performs read-only observation and records operator evidence; it does not run Capture/Restore/Retry.

## Required isolated desktop

Provision a disposable Windows 11 VM or a dedicated Windows test account/session on a resettable test system. Log in interactively, restore a known clean state, stop unrelated test activity, and manually close unrelated Explorer windows there. Do not treat a background remote-command host, Session 0, a restricted agent shell, or a flag alone as proof of isolation.

In that dedicated desktop, open `pwsh -NoProfile -Sta`. Record an operator attestation in a new file, for example:

```powershell
# Example only: fill Notes from actual provisioning evidence, not this placeholder.
$evidencePath = Join-Path $env:TEMP ('ResumeExplorer-session-'+[guid]::NewGuid().ToString('N')+'.json')
$evidence = @{
    Kind = 'DisposableVM' # or DedicatedTestAccount
    Dedicated = $true
    ComputerName = $env:COMPUTERNAME
    UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    SessionId = (Get-Process -Id $PID).SessionId
    DesktopName = 'Default'
    Notes = 'Identify the actual VM snapshot/test account, reset procedure and exclusive use approval here.'
}
$evidence | ConvertTo-Json | Set-Content -LiteralPath $evidencePath -Encoding utf8
```

This is a human attestation bound to automatically checked machine/SID/session/desktop values, **not automatic VM certification**. The harness additionally requires Windows build >=22000, PS Core major 7, STA, interactive nonzero SessionId, accessible input desktop matching the calling thread's Default desktop, reliable COM exposure, and an exact whole-desktop fixture scope. COM root windows are cross-checked against Win32 Cabinet/Explore top-level windows; missing exposure, hidden/foreign windows, duplicate identities and unsupported Raw/Root grouping fail closed.

```powershell
pwsh -NoProfile -Sta -File .\tests\Integration\Invoke-ExplorerSmoke.ps1 `
  -Mode Preflight -ConfirmIsolatedSession -SessionEvidence $evidencePath
```

Expected: `Ready`, E01/E02 `NotRun`, exit 2. With foreign Explorer windows, stop and inspect the isolated environment manually. No attempt is made to close windows or filter foreign paths out of a global Capture.

## E01 — manual A|B and C fixtures, then real Capture/Preview/Restore

1. With **zero Explorer windows** on the isolated desktop, prepare a fresh E01 root:

   ```powershell
   pwsh -NoProfile -Sta -File .\tests\Integration\Invoke-ExplorerSmoke.ps1 `
     -Mode Prepare -Case E01 -ConfirmIsolatedSession -SessionEvidence $evidencePath
   ```

2. Copy the returned `TestRoot` into `$testRoot`. Expected status `Prepared`, exit 2; E01 A/B/C folders and manifest/result exist under that unique root. Manually open exactly two Explorer windows: one containing tabs `E01\A` and `E01\B`, and another containing `E01\C`. No other Explorer windows may exist, including hidden ones. This manual setup is the only fixture-window creation step.

3. Execute once:

   ```powershell
   pwsh -NoProfile -Sta -File .\tests\Integration\Invoke-ExplorerSmoke.ps1 `
     -Mode Run -Case E01 -TestRoot $testRoot `
     -ConfirmIsolatedSession -SessionEvidence $evidencePath -AllowExplorerUiChanges
   ```

   The harness runs **real** `resume-explorer.ps1` subprocesses, serially, with `-NoProfile -Sta`: Capture -> Preview -> Restore. Paths are explicit and confined to this root. Scope is checked before Capture and again before Restore; snapshot groups must be exactly `{A,B}` and `{C}`. Report must be Completed/3 Verified with correct original indices, paths, snapshot hash and new-window fingerprints. The independent observer then requires two additional visible root windows/three tabs with correct grouping; original identities/paths/windows/process fingerprints remain unchanged within this observer process.

4. Expected automatic status: `AwaitingVisualReview`, exit 2, not Passed. Visually inspect all **four windows/six tabs**, distinguishing the original two from the new two. Check A|B and C in both sets; verify no original tab was changed. Record observed roots and a screenshot reference or detailed inspection notes. Then explicitly confirm:

   ```powershell
   pwsh -NoProfile -Sta -File .\tests\Integration\Invoke-ExplorerSmoke.ps1 `
     -Mode Confirm -Case E01 -TestRoot $testRoot `
     -ConfirmIsolatedSession -SessionEvidence $evidencePath `
     -ConfirmVisibleAndGrouping -VisualEvidence 'Actual visual inspection notes and screenshot reference.'
   ```

   Confirm checks saved JSON hashes, current visible scope, HWND/process fingerprints and paths again, then records E01 Passed/exit 0. Persisted COM pointer strings are never compared across processes. This command relies on truthful operator visual evidence; it cannot certify a screenshot's content.

5. Preserve the entire root. After confirming HWND ownership, **manually** close only these test windows. No automatic window/process or evidence cleanup exists.

## E02 — independent missing-B restore and actual targeted Retry

1. Use another clean desktop state with zero Explorer windows; rerun Preflight. Prepare with `-Mode Prepare -Case E02` (same evidence flags). A new root is returned. Only `E02\A` exists; **do not create B or open fixture windows manually**. E02 starts from zero windows, unlike E01.
2. Run with `-Mode Run -Case E02 -TestRoot <new-root>`, the evidence flags, and `-AllowExplorerUiChanges`.
3. The runner creates an independent legitimate Snapshot v1 `[A,B]`, then performs one real Restore to `retry-root.json`. It requires A Verified, B SkippedInvalidPath and all B attempt flags false. It independently observes exactly one visible A window and validates its report fingerprint.
4. Only now does the harness create B, then invoke real PreviewRetry. It requires the sidecar's RunId/hash and sole HWND fingerprint to match that owned A window. After a fresh scope/identity check it invokes real Retry for **Group 1 / Item 2 / the verified HWND**, without IncludeUncertain.
5. It verifies one new child report under `RetryRuns`, original ItemIndex=2 only, Verified, parent/root lineage, target fingerprint and snapshot hash; parent/snapshot/sidecar bytes stay unchanged. The original A identity/path/window remains unchanged and exactly one B tab is added in that same visible window.
6. Automatic status is AwaitingVisualReview/exit 2. Manually verify the visible A|B window and confirm with `-Mode Confirm -Case E02` and actual visual notes, as for E01. Preserve all evidence; cleanup is manual and restricted to positively identified test windows.

## Failure and evidence handling

- A fixture-local OS `FileShare.None` lock prevents concurrent harness invocations from consuming the same Prepared root. This is not the production Task-3 CLI guard; every public CLI call still follows production locking rules.
- Once Run starts, it consumes that root even on an exception. Re-running Run with that root is rejected; existing terminal result evidence is preserved. Stop at the first uncertain result or nonzero CLI exit. There is no automatic replay or navigation repair.
- `smoke-result.json` records runtime, attestation, command arguments/exit codes, independent before/after views, foreground HWND (diagnostic only), artifact hashes and status. Each CLI has its own stdout/stderr files. Snapshot, parent report and sidecar evidence are never edited to manufacture a retry.
- If a CLI or COM/UIA call hangs, the last persisted phase/command-start record may remain Running. There is **no hard wall-clock guarantee**. Do not kill Explorer, remove another process's lock, or automatically retry. Recover the isolated VM manually and retain evidence for Issue-4.
- Prepare/Run/Confirm never use the default snapshot or production Runs directory. A future production global lock outside Runs, if implemented, is respected. The runner does not weaken execution policy, restart Explorer, use SendKeys/clipboard, or close any window.
- Session attestation, observations, stdout/stderr and JSON can contain private paths, user SID and error text. Keep them local to the test environment; do not commit raw live evidence or this session attestation. Redact before sharing.
- Exact scope checks reduce races but do not create a transaction with Explorer or exclude external actors. Keep the test session exclusively controlled. The native observer's Cabinet class assumption and all actual PS7/COM/UIA behavior remain subject to live acceptance on the supported build.

## Delivery evidence (2026-11-02)

- PS7.6.1 deterministic suites: Issue2 39, RestoreSummary 17, harness 21 (77 total), all Exit 0.
- Actual public-entry default: NotRun/NotAuthorized, E01/E02 NotRun, exit 2. Import-only test performs no dispatch.
- Harness tests use synthetic observations/CLI substitutes for orchestration and safety assertions. Their AwaitingVisualReview values are not live results and are never promoted as release evidence.
- Native helper compilation and managed assembly-load probe may be recorded separately; neither enumerates Shell Windows nor searches an actual AddButton.
- **Subsequent live acceptance: E01/E02 completed in the user's VM, overall exit 0. Task-5 Closed; [provenance and version/traceability limits](TASK5-VM-ACCEPTANCE.md).**
