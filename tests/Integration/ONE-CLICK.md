# One-click Explorer smoke — guided VM workflow

In the **isolated Windows 11 VM**, with PowerShell 7 installed and `pwsh.exe` on PATH, double-click:

```text
tests\Integration\Run-ExplorerSmoke.cmd
```

Or start it in a terminal:

```powershell
pwsh -NoProfile -Sta -File .\tests\Integration\Start-ExplorerSmoke.ps1 -Run
```

The launcher works relative to its own file location, not the current working directory. No administrative elevation or execution-policy bypass is requested. If policy blocks execution, stop and follow the VM's normal policy instead of weakening it.

## What is automatic

1. Present the isolated-VM/dedicated-account GUI authorization prompt. If accepted, record the actual machine/SID/session/desktop plus the operator's VM snapshot/exclusive-use notes; validate the existing runtime/session gates. The notes are a human attestation, not automatic VM certification.
2. Create a unique TEMP suite evidence directory. Run four offline suites (currently 39+17+21+14 tests) and require their actual PASS counts and exit codes. Failures stop the suite before any Explorer operation.
3. Perform the existing read-only empty-desktop Preflight. Foreign/hidden/incomplete Explorer scope blocks all setup GUI actions.
4. Prepare a fresh E01 root. Bootstrap A|B and C by calling the **real public CLI Restore once** with a new `setup-snapshot.json` and `setup-report.json`. These are separate from E01's `capture.json` and `restore-root.json`. Check all three items Verified, snapshot hash, visible/grouped independent observations, report fingerprints and AddButton capability. No fabricated report or SendKeys is used.
5. Only when setup is verified, invoke the existing E01 Run (real Capture -> Preview -> Restore) and stop for operator visual review. All original observer, report and hash checks remain in force.
6. After actual E01 review and manual closure of its test windows, verify the entire desktop is empty again. Prepare an independent E02 root and invoke the existing missing-B Restore -> PreviewRetry -> targeted Retry workflow.
7. Stop for actual E02 visual review, then print and save the combined suite result. Overall Passed requires **both** original harness Confirm calls to return Passed.

The automatic bootstrap depends on Restore itself working. If setup produces OutcomeUnknown, hidden/wrong windows, ambiguous identity, a nonzero exit or a partial report, it stops before E01 Capture. There is no automatic retry. The original manual-fixture entry in [README](README.md) remains available when diagnosing setup behavior separately.

## What still requires you

- At startup type `VM` or `TESTACCOUNT` **only in the actual dedicated test environment**, then provide real provisioning/approval notes. Canceling performs no runtime probe or GUI operation. Merely entering a value cannot create isolation; the same runtime, desktop and full Explorer-scope checks still apply.
- E01: inspect **four visible windows / six tabs**. Original fixtures and restored fixtures must each have A|B and C, and originals must remain unchanged. Type `PASS` and enter real inspection notes, optionally with a screenshot reference. Blank/refusal leaves AwaitingVisualReview and prevents E02.
- Between cases, manually close **only the four positively identified E01 fixture windows**, preserve all evidence, then type `CONTINUE`. The observer must independently confirm zero remaining Explorer windows. If you cannot identify a window, stop; do not close unknown windows.
- E02: inspect one visible A|B window, original A unchanged and exactly one new B tab. Type `PASS` and record actual notes. E02 windows remain open for manual cleanup after the suite.

Thus this is **one launch with guided confirmations**, not an unattended GUI acceptance test. It removes the repeated commands, path copying, session-JSON preparation and manual fixture construction. It does not remove visual acceptance or the no-auto-close constraint.

## Results, interruption and concurrency

Exit codes match the original runner: 0 Passed, 1 Failed, 2 NotRun/pending review, 3 Blocked. The `.cmd` keeps the terminal open so you can inspect the output and exit code. The PowerShell entry **without `-Run`**, and dot-source import, have zero dispatch/GUI side effects and report NotRun (exit 2 for direct invocation).

The suite directory is `%TEMP%\ResumeExplorer-E2E-Suite-<GUID>`, containing `session-evidence.json` and `suite-result.json`. Each case still owns a separate `%TEMP%\ResumeExplorer-E2E-<GUID>` root. The combined result lists both roots, case status, offline counts and phase-start records. E01 setup keeps its separate snapshot, report, CLI stdout/stderr and independent observation. Core Run retains all original reports, sidecars, hashes and logs.

A cooperative `ResumeExplorer-E2E-OneClick.lock` under the current user's TEMP prevents concurrent one-click launchers sharing that TEMP. It is held until the suite exits and the empty lock file is retained. A suite-local lock and the existing case-local lock also protect their own artifacts. These locks do not replace or bypass production Task-3 locking, protect different TEMP locations, or exclude manual/third-party Explorer activity. Do not delete an active lock.

Any first nonzero CLI exit, unverified setup or case, hash mismatch, stale fingerprint or unexpected scope stops later actions. The same setup/root cannot be replayed after an attempt. A new launch creates new roots; first inspect and manually organize any prior fixture windows in the VM, so the next empty-scope gate can pass. Pending cases can be inspected or Confirmed through the original manual runner; the one-click entry does not resume or repeat an old suite.

If a synchronous CLI/COM/UIA operation hangs, there is no hard timeout and no automatic Explorer/process termination. Preserve the suite/phase logs and recover the disposable VM manually. Raw evidence contains user SID, paths and error text; keep it local and redact before sharing.

## Verification status

Four suites pass on PowerShell 7.6.1: **39+17+21+14 = 91 offline tests**, including 14 new orchestration tests. New tests use synthetic CLI/observer/prompt adapters, including synthetic terminal Passed states solely to test suite transitions; they are **not live E01/E02 evidence**. Existing tests and production code remain unchanged.

**Live one-click bootstrap, E01 and E02 are NotRun** because no isolated Windows GUI environment is available. Task-5 remains open; this convenience entry does not change its release gate.
