# Issue-3 — Restore focus / foreground independence: RCA-first plan

Review: 2026-11-02 | Status: **Proposed / not reproduced / no production change** | Priority: P2
Scope: `Backlog.md` Issue-3. This plan is for **tolerating user foreground/focus changes while Restore is running**, not Feature Request-1's separate request for invisible, non-focus-stealing Restore.
Historical example: `02e5f26b61da4a1ba503bea37d15323f.json`; report includes private folder paths; do not check in raw data.

## 1. Decision / evidence

**Do not apply a speculative focus fix yet.** There is no controlled before/after evidence that clicking Chrome, Visual Studio, or another Explorer window causes an incorrect navigation, timeout, or failed transaction. Temporal coincidence in the earlier 18-item report is insufficient. Issue-4 owns synchronous COM/UIA latency and deadline overruns; compare both, but do not conflate them.

Verified from the current implementation (`resume-explorer.core.ps1`):
- `New-ExplorerAdapter` uses `Get-NewTabInvokePattern` (UIAutomation `AutomationId=AddButton`, `InvokePattern` on the target **root HWND**), `Shell.Application.Windows()` views, and `Navigate2` on the resolved view's COM object. There are no `SendKeys`, screen-coordinate clicks, or explicit `SetForegroundWindow` calls in this path.
- `Get-ExplorerObservation` enumerates all Explorer views, records raw HWND/root HWND/PID, COM `IUnknown`-derived identity, path and window fingerprint, and rejects incomplete/conflicting observations. `Get-TargetViews` groups by **raw HWND**; the root HWND is for UIA lookup. Do not casually switch grouping to root HWND.
- `Invoke-TabTransaction` obtains a stable baseline, checks it again before a **single** Invoke, requires a unique stable newly observed identity, revalidates before a **single** Navigate, and requires the candidate/path to remain stable before Verified. Side-effect-attempt flags are atomically checkpointed **before** those calls. Ambiguity/unknown outcome is not automatically retried.
- New groups call `OpenWindow` with `-WindowStyle Normal`; showing/activating new Explorer windows is allowed by present behavior, even though FR-1 requests otherwise.
- A top-level single-instance guard is a separate concern; it does **not** prevent a human or third-party process from changing target Explorer state during Restore.

Unverified hypotheses (not root causes): (H1) a foreground change alters UIA accessibility/availability; (H2) switching the target active Tab affects which Shell COM views are exposed or which COM object receives navigation; (H3) another user action creates a candidate or changes a baseline, correctly triggering a conservative abort; (H4) slow Shell/UIA enumeration masquerades as focus failure (Issue-4); (H5) window creation itself shifts focus, independently of user mouse actions (FR-1).

## 2. Behavioral contract and boundaries

- **A: Foreground other app** (Chrome/Visual Studio) and **B: foreground another Explorer window** without changing the target: should not by themselves cause wrong-Tab navigation, identity substitution, or a focus-specific failure. Target window may be in background. Do not promise latency invariance under arbitrary OS load.
- **C: switch active Tab inside the target window**: desired independence where Explorer exposes stable, distinguishable identities; **not proven**. Investigate whether active-Tab changes are indistinguishable from identity disappearance or whether UIA AddButton has changed semantics. Never make a best guess.
- **D: create/close/navigate a Tab in the target** and **E: close/recreate the target window**: shared state changed. A conservative `PreconditionFailed` or `OutcomeUnknown` is acceptable; automatically attaching to another Tab or reissuing Invoke/Navigate is not.
- **F: user interacts with another Explorer window while Restore creates a new group**: evaluate new-window matching separately. A matching path alone is not proof of ownership; ambiguous new windows must not be hijacked.
- Foreground switch may change responsiveness; distinguish delayed observation from identity changes and from the actual navigation side effect. **No guaranteed 100% success** under concurrent edits of the target.

## 3. Phase 0 — baseline and safe setup

1. Preserve a clean Git baseline and unchanged snapshot/report schemas. Review the existing `tests/Issue2.Tests.ps1`, `tests/RestoreSummary.Tests.ps1` and `ISSUE2-VALIDATION.md` before tests; existing behavioral assertions are regression contracts.
2. Use a **resettable interactive Windows VM** or dedicated test user/session, never an active work Explorer. Create a disposable local folder fixture (unique paths) with 2–3 windows and 2–4 Tabs each; leave unrelated real windows untouched. Use small, controlled runs before load testing.
3. Hold snapshot, existing window count, machine/session, CLI version, timeout parameters, and Explorer state constant. Record Windows build/PowerShell version and whether any shell extension / OneDrive / Google Drive is active. Save sanitized evidence only.
4. Establish at least three no-interaction repeats before intervention. Collect run statuses and pre/post actual Tab paths; do not use report `Verified` alone as evidence of no unintended navigation.

## 4. Phase 1 — focused reproduction / instrument only if needed

| Case | Interaction timing | Expected safety result |
| --- | --- | --- |
| Control | No mouse/keyboard interaction | Baseline latency and success/unknown distribution |
| A1/A2 | Switch foreground to Chrome/VS before Invoke; after Invoke/before Navigate | No wrong navigation; compare outcomes to control |
| B | Activate another Explorer window, without editing target Tabs | Target identity/path remain attached to original target |
| C1/C2 | Switch active Tab in target before Invoke; after candidate detected | Verify observed identity/path stability or conservatively stop |
| D1/D2 | Add/close/navigate target Tab during detection/navigation | No ambiguous candidate selection; no navigation of an unrelated Tab |
| E | Close/recreate target window during a pending transaction | Fingerprint mismatch/window loss, no silent replacement |
| F | Create unrelated window with same requested path during group creation | No false new-window ownership; ambiguity must fail closed |
| Slow-control | Artificially delayed Observe, no user interaction | Separate deadline overshoot from focus-specific effects (Issue-4) |

Timing must be repeatable: use an adapter-driven deterministic harness for state changes; for interactive E2E coordinate actions by explicit phase markers rather than relying on arbitrary sleep intervals. Do not introduce new production synchronization hooks solely to automate GUI tests.

Capture **per attempt**: group/item, phase, monotonic elapsed, phase entry/exit, actual foreground HWND if cheaply available, target raw/root HWND, PID/start/session fingerprint, observed identity set, selected candidate identity, path readability/path match, duplicate/read errors, `InvokeAttempted`/`NavigateAttempted` flags, ReasonCode, and actual Explorer Tab paths after the run. Do not log raw private paths to Git; avoid extra synchronous COM property reads merely for telemetry. Issue-4 owns fine-grained Observe/UIA wall-clock measurements; reuse its bounded diagnostics rather than add a second instrumentation framework.

## 5. Phase 2 — root-cause decision and minimal fix (conditional)

Use evidence to choose **one narrow change**, not a generalized window-activation subsystem:

1. **No reproducible focus-specific failure:** document the matrix and close Issue-3 as verified/no defect; do not modify core.
2. **UIA AddButton changes or is unavailable only when inactive:** determine if target-root lookup and InvokePattern can work without activating the target; prefer a narrowly scoped UIA lookup/revalidation change with deterministic tests. Never substitute `SendKeys`, global focus stealing, blind clicks, or assumed Tab order.
3. **COM tab enumeration/identity differs with active Tab:** capture controlled before/after sets and prove whether `RawHwnd`, `RootHwnd`, `IUnknown` identity, or COM object lifetime is responsible. Any alternative identity/selection method must prove unique ownership, stable baseline and post-Invoke identity across observations; ambiguous cases remain unknown. Do not simply use the active Tab, last view, path-only matching, or change to root-HWND grouping.
4. **Concurrent user edits of target:** treat as a legitimate conflict. Improve diagnostic ReasonCode/summary only if necessary and backward-compatible; do not forcibly change user's active Tab or silently retry.
5. **Only slow synchronous calls/deadline overshoot:** transfer measured evidence to Issue-4. A timeout increase by itself is not a fix.
6. **Window creation itself steals focus:** route to FR-1; do not make invisibility an Issue-3 acceptance requirement.

For any selected change, first define the smallest failing fixture, expected safe outcome, existing contract impact, and rollback condition. Preserve the public CLI parameters, report/snapshot V1 reader, original item indices, identity/fingerprint/reliability gates, three reliable baseline observations, stable-duration checks, single Invoke/Navigate, pre-side-effect atomic checkpoint, `OutcomeUnknown`, and explicit PreviewRetry/Retry safeguards. If any contract must change, do a separate compatibility review and update version/docs/tests.

## 6. Tests, acceptance gates, and delivery

**Deterministic tests (CI-capable):** add `tests/Issue3.Focus.Tests.ps1` using the existing adapter/fake-clock conventions. Cover target foreground change with stable identity; unrelated Explorer foreground change; active target Tab switch with unchanged observable identity; target identity disappearance/replacement; two new candidates from human action; concurrent Tab close; new window with same path; delayed observations and no duplicate side effects. Assert correct target view/path, max one Invoke and one Navigate, checkpoint before attempted side effects, conservative status on uncertainty, and compatibility with existing reports. Modify existing tests only with a separately documented, verified reason; never weaken assertions to pass.

**Interactive E2E (not regular hosted CI):** run the A–F matrix on the isolated desktop, at least three controlled runs per case initially, increasing samples if unstable. Compare with control using failures by phase/ReasonCode, verified count, duration, and erroneous-navigation count. The **primary hard gate is zero observed navigation of an unrelated existing Tab**, including during uncertain outcomes; any such event blocks release. For A/B, no focus-caused identity substitution or reproducibly increased failure rate versus control; for C, either proven-safe navigation or conservative, explainable stop; for D/E/F, fail closed when ambiguous. Do not claim absence of intermittent Windows issues solely from three runs.

**Regression:** run all existing deterministic tests unchanged, verify `PreviewRetry`/`Retry` on sanitized fixtures, and ensure Issue-2 visibility/summary behavior remains intact. Never run disruptive tests against the daily-use Explorer, restart/terminate Explorer, or clean up unknown windows/processes.

**Deliverable order:** (1) record baseline/fixture and control, (2) add focused deterministic regressions for reproduced case, (3) reproduce and isolate causality with safe E2E, (4) implement only if evidence warrants, (5) run regression/E2E and document constraints, (6) update Backlog/README/version and close, defer, or re-scope with evidence. No production change is authorized by this planning review.

## 7. Dependencies / status

- **Issue-2:** existing safety invariants must remain intact; no new focus workaround may regress them.
- **Task-1:** deterministic test infrastructure may be reused, but this issue need not wait for a full testing-platform redesign.
- **Issue-4 (P1):** shares measurements of slow observations; an Issue-3-specific code fix depends on eliminating timing-only explanations, not on complete Issue-4 closure. Prioritize Issue-4's independently verified correctness risks.
- **Issue-5 / Issue-6:** process lifecycle and Google Drive shell hang are separate evidence streams; no assumed causal link.
- **FR-1:** non-disruptive invisible Restore is a distinct goal; no coupling or unpromised change to current visible windows.
- **Task-3:** a single-instance CLI lock prevents competing tool commands, not human activity; it is neither a fix nor a precondition for the focus matrix.

**Current result:** design/review only. No controlled A–F results yet, no verified focus root cause, no production fix, and no basis to mark Issue-3 Completed.
