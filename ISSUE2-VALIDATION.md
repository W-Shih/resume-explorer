# Issue-2 implementation validation

Date: 2026-11-01. Candidate: `0.1.0-beta.1+issue2`.

The implementation covers stages B/C and adds observation traces for stage A. The actual Group 2 failure has not been reproduced in the original Horizon VDI environment. No production RCA is claimed. Stage D live acceptance is still pending; the version is deliberately not promoted to beta.2. Issue-2 is closed as implementation-complete only; closure does not imply successful live acceptance or a confirmed production RCA.

## Automated checks

Run `tests/Issue2.Tests.ps1` in PowerShell. It uses a fake clock and injected Explorer adapters, with no real Explorer operations. Tests assert action counts, identity selection, final states, persistence and original indices. No third party modules are required.

Covered scenarios include normal and 12-second delayed creation, detection timeout, duplicate identities, multiple candidates, multiple-to-single history, identity replacement, disappearing baseline, unstable baseline, unavailable controls, window loss, capped error backoff, recovery after more than three errors, error streak reset, clipped deadline, late candidate stability, configurable deadlines, invalid configuration, uncertain Invoke, navigation exception/timeout, old matching paths, checkpoint failure, group isolation, invalid paths, path roots, stale fingerprints, retry selection, completed/uncertain child runs, atomic report replacement, new-window ambiguity/deduplication, interrupted stability, transient enumeration failure, full-run checkpoint integration and global Shell failure.

The implementation stores phase-labelled observations inside each item's `Diagnostics.Samples`, including raw/deduplicated counts, Raw/Root HWND, process fingerprint, identity, path and read errors. This intentionally keeps the complete trace in the checkpoint rather than requiring a separate JSONL file. Reports may grow with group size and configured deadlines. COM references are retained only in live transactions, never serialized.

Local results: **39 adapter/integration tests passed on PowerShell 7.6.1**, Windows build 22631. Windows PowerShell 5.1 parser accepted the core; executing the 5.1 test script was blocked by the machine execution policy. The policy was not changed or bypassed, so 5.1 runtime compatibility remains unverified. A read-only native Shell COM observation in the restricted agent process returned access denied (`0x80070005`); this is an execution-environment limitation, not evidence about the original Issue-2 root cause.

## Visible-window regression (2026-11-01)

Report `535b092885594426af03bded40354d85` confirms six window creation attempts, twelve tab creation/navigation attempts and eighteen Verified items. The referenced diagnostic conversation recorded all six created HWNDs as existing but invisible. The production OpenWindow adapter passed `-WindowStyle Hidden`; it now explicitly passes `Normal` to restore visible-window launch behavior. Path/identity verification does not test desktop visibility or focus.

The new regression test invokes the actual production adapter with an intercepted Start-Process. It checks one Explorer launch, quoted paths with spaces and WindowStyle Normal. It failed on the Hidden implementation and passes after the fix. The previous tests replaced OpenWindow with a fake, so they could not detect this launch-parameter regression. No full Restore was re-run and no old hidden windows were altered during this fix; on-desktop visibility after a real launch remains a live acceptance check.

## Restore summary enhancement (2026-11-01)

Implemented pure Get-RunSummary analysis and Console rendering at the existing Write-RunSummary call site. Restore/Retry algorithms, Complete-Run checkpoint/error flow, CLI dispatch, SchemaVersion 1 and report persistence remain unchanged. There are no new log files or Explorer operations.

PowerShell 7.6.1 results: **39 existing Issue2 tests plus 17 new RestoreSummary tests passed (56 total)**. The summary suite covers plan cases S01-S17: complete/partial/empty/interrupted results, zero Verified, interrupted runs with all items Verified, every unverified status, duplicate paths, original numeric indices, safely quoted absolute commands, unknown/missing fields, escaped controls, child-run scope, unchanged input/report bytes/schema, final checkpoint failure with JSON fallback and original exception, and WarningPreference Stop. S18 is covered by the existing PreviewRetry/Retry integration test in the 39-test suite, including preview fingerprints and child replay protection.

Windows PowerShell 5.1 execution of the summary suite was blocked by the existing execution policy; no policy was changed or bypassed. No actual Restore or live Explorer visibility test was performed for this presentation-only enhancement. Original Issue-2 and visible-window live acceptance remain pending.

## Task-4 test-only cross-version correction (2026-11-02)

The historical Windows PowerShell 5.1 runtime limitation was resolved for this validation by running outside the restricted agent sandbox under the existing CurrentUser RemoteSigned policy; no execution policy was changed or bypassed. Baseline on PS5.1.22621.6931 reproduced S01-S15 passing then S16 failing (Exit 1), while PS7.6.1 passed 17/17 (Exit 0). Issue2 baseline passed 39/39 on both versions.

Only S16's whitespace-sensitive fallback JSON assertion changed. The test now extracts exactly one InformationRecord JSON body, parses it, and verifies schema, RunId, state, item count, group/item indices, status and requested path. Original exception identity, one checkpoint warning, report-path display and no false saved/updated message checks remain intact. Twelve negative fixtures must be rejected (missing, duplicate, malformed, unrelated/missing schema, wrong schema/run/state/count/group/index/status/path). They execute within S16, preserving the suite's 17-test count.

Final native-process results: PS5.1.22621.6931 Summary **17/17**, Issue2 **39/39**; PS7.6.1 Summary **17/17**, Issue2 **39/39**, all four **Exit Code 0**, with actual PASS records counted. Production core, CLI and schemas remain unchanged, and no real Explorer operation was performed. This closes Task-4's test-baseline gate, not Explorer E2E or Task-3 lock acceptance. See [Task-4 archived evidence](plans/DONE/resume-explorer-Task-4-restore-summary-s16-regression-plan.md).

## Task-5 initial harness delivery (historical; later VM acceptance below)

Standalone runner, independent observer, operator SOP and deterministic safety tests were added under `tests/Integration` and `tests/ExplorerSmoke.Tests.ps1`. Production CLI/core and existing tests are unchanged. The user requested runner/offline delivery because no isolated environment is available; the agent also has no separate Windows VM or dedicated interactive desktop. The execution sandbox is not GUI isolation.

PowerShell 7.6.1 suites: Issue2 **39/39**, RestoreSummary **17/17**, smoke harness **21/21**, all **Exit 0**, with actual PASS records counted. Harness tests cover denied consent, runtime/session mismatch, foreign/incomplete/hidden scope, original identity/path/fingerprint preservation, duplicate/grouped paths, snapshot/report assertions, RCW-free evidence, fresh owned roots, replay/active-lock rejection, missing visual review, synthetic E01/E02 command routing, first-error stop, tampered evidence and safe default/import behavior. Synthetic routing stops at AwaitingVisualReview and is not live evidence.

Actual default public entry returned **NotRun / NotAuthorized, Exit 2** without invoking COM/UIA or any CLI. A separate `pwsh -Sta` load-only probe compiled the Win32 helper and loaded UIAutomationClient/UIAutomationTypes. During that initial agent delivery no Shell enumeration, AddButton search or real CLI GUI operation occurred, and live cases were NotRun. This historical status was later superseded by the user's completed VM run below; the safe-default behavior remains unchanged.

## One-click Task-5 convenience entry (2026-11-02)

Added a guided `.cmd` / PowerShell launcher and a separate orchestration helper. It uses the existing safety-gated harness for both cases, automatically bootstraps E01 through one real public CLI Restore with separate setup evidence, and still requires truthful isolated-session attestation, two visual reviews and manual closure of known E01 windows. No production or existing-test changes. Without `-Run`, and on import, no dispatch occurs. A cooperative same-TEMP launcher lock prevents concurrent one-click suites; existing harness/production locks are respected.

PowerShell 7.6.1: 14 new synthetic orchestration tests plus existing 39/17/21 suites, **91 total PASS, all Exit 0**. New coverage includes no-consent/no-dispatch, runtime/baseline/foreign-scope rejection, one-attempt setup with failure/unverified evidence, no replay, absent visual review, manual-close refusal and independent empty-scope recheck, first-case stop, two-review/two-root ordering, persisted phases, coordinator lock rejection and safe public default/import. Synthetic terminal Passed results validate control flow only. Live cases were NotRun at initial delivery; subsequent user-executed acceptance is recorded below. See [one-click SOP](tests/Integration/ONE-CLICK.md).

## Task-5 Closed: user-executed VM acceptance (2026-11-02)

The user's latest two screenshots show the one-click VM run completing E01 and E02 operator PASS/visual notes, the manual-close transition, E02-Confirm, Phase Complete, Error null and overall **Exit Code 0**. The reviewed launcher reaches Complete only after both case Confirm calls return Passed. Its four offline suites also show 39/17/21/14 passes, all Exit 0. On this **user-provided VM evidence**, Task-5 is Closed and its [plan is archived in DONE](plans/DONE/resume-explorer-Task-5-powershell7-explorer-e2e-smoke-plan.md).

See the [acceptance record](tests/Integration/TASK5-VM-ACCEPTANCE.md) for screenshot provenance, latest case roots and scope. The agent did not rerun GUI, independently parse the VM's reports, or obtain exact VM Windows build/PS minor/commit/SuiteRoot values from the screenshot regions. Runtime gates establish the minimum Win11/PS7/STA constraints of the completed runner; do not substitute the agent machine's runtime versions. Raw VM evidence should remain preserved for detailed traceability. This closeout is documentation only, not a production fix, beta.2 release certification or universal Windows/VDI compatibility claim.

## Live acceptance still required

- Reproduce the original failure with the diagnostic candidate; record Windows build, PowerShell version, group sizes, load, concurrent interaction and raw/root grouping.
- Produce a redacted trace before attributing the failure to duplicate enumeration, delayed exposure, incomplete baseline, COM replacement or concurrent tab operations. Synthetic tests demonstrate handling of these conditions; they do not establish the real root cause.
- Verify the original two-window/three-tab scenario and six-group configurations with duplicate paths, cold and slow VDI responses, concurrent operations in another window, target-window tab additions/closures and closed/stale retry targets.
- Complete a partial restore followed by an explicit subset retry into a previewed target; verify no unrelated existing tab is navigated. Keep reports and retry family together.
- Perform 20 normal multi-group restores in the original supported environment and record every outcome and duration. Test windows are organized manually; the product never closes windows or kills Explorer.
- Validate RawHwnd tab grouping and COM identity stability on that environment. If unreliable, keep conservative stops and design a separate identity mapping rather than guessing candidates.

No strict wall-clock limit is claimed for blocking synchronous COM/UIA calls. Background/no-focus restore, ZIP/Shell namespaces, restart, GUI and snapshot history remain outside this change.
