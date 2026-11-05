# Task-5 VM smoke acceptance — user-provided evidence

**Original guided-workflow decision: Task-5 Closed / Completed, 2026-11-02 (America/Tijuana).** The user ran the guided one-click workflow in a Windows 11 test VM and supplied the final console screenshots. This records user-executed acceptance, not an agent-run or independently replayed GUI test. The later automatic SC_CLOSE workflow also has a successful user VM smoke run; see the final section dated 2026-11-03.

## Evidence reviewed

Source: the latest two screenshots supplied in this chat, named `codex-clipboard-a6e1a57e-c7bb-445c-bd18-7a8ee0429891.png` and `codex-clipboard-a1d45e39-bfa8-4fc8-bdbc-a11db6f48d25.png`. Raw screenshots and VM reports are not copied into this repository because they contain private paths/user information.

| Item | Visible evidence / supported conclusion |
| --- | --- |
| Environment statement | Operator selected `VM`; environment notes `Temp-VM-Ad001` (operator label, not independently verified computer identity) |
| Offline baseline | Issue2 39/39, RestoreSummary 17/17, ExplorerSmoke 21/21, OneClick 14/14; each Exit 0 |
| E01 | Operator typed PASS and supplied grouping/ownership notes; E01 Confirm completed before manual-close transition and E02 start |
| Manual transition | Operator typed CONTINUE after closing E01 fixtures; E02 started after the harness's independent empty-scope gate |
| E02 | Operator typed PASS and supplied A/B visual notes; E02-Confirm was reached and completed |
| Overall | Phase `Complete`, completion step ExitCode 0, `Error: null`, terminal `Explorer smoke exit code: 0` |
| Completion time | Screenshot UTC `2026-11-03T06:04:19Z`, corresponding to **2026-11-02 22:04:19 America/Tijuana** |

The reviewed launcher only reaches Complete/exit 0 after both existing harness Confirm calls return Passed. This supports **E01 Passed and E02 Passed for this run**, with automated observer/hash/report assertions and the user's explicit visual confirmation. The agent did not separately inspect the VM desktop pixels or parse its original report files.

Case evidence locations shown by the latest screenshots, expressed without a user profile path:

- E01: `%TEMP%\ResumeExplorer-E2E-3084e4c832e5455587e6a65ff0c9f4d3`
- E02: `%TEMP%\ResumeExplorer-E2E-1563ffefa65c427a977779b6678b63d7`

The latest run's SuiteRoot is not visible in the supplied screenshot regions and is **not inferred from the earlier run**. Earlier screenshots ended with E02 AwaitingVisualReview/exit 2 and belong to different roots; they are not evidence of this final suite's completion.

## Scope of acceptance

- E01: real setup Restore, Capture -> Preview -> Restore, two original and two new visible windows, three tabs per set (A|B and C), original identity/path/group preservation, report 3/3 Verified, and operator visual review passed according to the completed runner flow.
- E02: real A Verified / B SkippedInvalidPath fixture, PreviewRetry and explicitly targeted Item 2 Retry without IncludeUncertain, child 1/1 Verified, unchanged parent/snapshot/sidecar hashes, original A preserved and one B tab added, plus operator review passed according to the completed runner flow.
- Runtime/session/scope gates passed in that run: Windows 11 build >=22000, PowerShell Core major 7, STA, dedicated interactive-session attestation, desktop/ownership checks and independent COM/Win32/UIA checks. **The exact VM Windows build, PowerShell minor/patch, session fingerprint and repository commit are not visible in these screenshots and were not independently extracted.** Do not substitute the agent machine's PS7.6.1/build22631 for the VM values.

For full build-specific traceability, retain the VM's complete suite root (session-evidence/suite-result) and both case roots (smoke-result Facts, snapshots, reports, sidecars and CLI logs). Exact runtime metadata is generated there by the harness; its raw values and artifact hashes have not been re-audited by the agent. Further release certification or reproduction should obtain those original facts rather than invent them.

This closes the requested small smoke task on **user-reported VM acceptance**. It does not establish compatibility across all Windows/PowerShell/VDI builds, repeated reliability, every GUI failure path, or fixes for Issue-3/4/5/6, Task-3 locking, FR-6 cleanup, or the full Task-1 framework. No production change, version bump, GUI rerun or raw-report modification is part of this closeout.

## Automatic whole-window close acceptance (2026-11-03)

The user reported “通過了” after updating the window-close implementation and supplied `codex-clipboard-065782ae-c2c6-4e4a-a242-628f5fde06d3.png`. This is a new successful run, separate from both the original guided acceptance and the failed WM_CLOSE runs. The source screenshot remains outside the repository.

| Item | Visible evidence / supported conclusion |
| --- | --- |
| OneClick offline suite | 47 PASS, ExitCode 0; screenshot does not show the other three rows. The independently executed local baseline for this implementation was 39/17/23/47 = 126 PASS |
| Overall | `Explorer smoke exit code: 0`, `Error: null`, user confirms success |
| Review mode | `VisualReview: NotRun`: normal automatic Verify mode, not a missing required approval or claimed human inspection |
| Saved existing configuration | `ExistingSnapshot` points to `existing-snapshot.json` under the new suite root; supports the save-before-close path, but does not reveal the initial number of windows/tabs |
| New suite root | `%TEMP%\ResumeExplorer-E2E-Suite-68d2f08e58f5445ea0c5e4f5d8ba3781` |

The reviewed launcher returns exit 0 only when both E01 and E02 verification calls pass, both case cleanup calls finish, and the combined suite returns Passed. In the context of the user's updated-run report, this supports **one successful real VM run of the automatic workflow**, including existing-configuration saving/closure and E01/E02 verification/cleanup. E01's fixture exercises multiple windows and A/B tab grouping. The E01/E02 status rows, individual case root IDs, final empty-scope samples and command records are not visible in this screenshot and were not independently parsed by the agent.

This supplies the previously missing minimal live evidence for the SC_CLOSE correction. Exact VM build, PS minor/patch, commit, session facts and completion timestamp are not shown; local review revision `02849d0` must not be claimed as the verified VM commit. Preserve this suite root and its referenced case roots for traceability.

The detailed follow-up [plan](../../plans/DONE/resume-explorer-Task-5-multi-group-close-regression-plan.md) records remaining extended-matrix gaps: three consecutive two-window runs, explicit close-without-save/cancel, larger/duplicate-path groups, zero-existing-window startup and live negative cases are not all established by this screenshot. **The main automatic smoke passed; the extended matrix is not declared fully complete.** No code or tests changed as part of recording this result, so no new GUI or unit-test run is required for this documentation update.

## Persistent Snapshot and manual Restore acceptance (2026-11-03 client date)

The user supplied `codex-clipboard-aad1bd8b-8e6f-4e64-bb5d-7b2fad699681.png` and explicitly confirmed both the test passing and successful restoration using the displayed command.

| Item | Evidence / conclusion |
| --- | --- |
| Supervisor summary | `測試結果: Passed` and `Explorer smoke exit code: 0` |
| Persistent Snapshot | `%LOCALAPPDATA%\ResumeExplorer\Snapshots\BeforeSmoke\3274dc4603a3417881d83823caf91b4c.json` |
| Durable instructions | Same directory and RunId, suffix `.restore.txt` |
| Command | Screenshot shows complete absolute pwsh, tool and Snapshot paths, with `-NoProfile -Sta -File`, `-Action Restore` and `-Snapshot` |
| Actual restoration | User reports successfully restoring via that command; the separate Restore Report and item-level Verified counts are not shown |

This supports one successful real VM run of persistent saving, foreground worker/supervisor interaction, both E01/E02 verification and cleanup (required by the reviewed success gate), final recovery guidance, and user-executed restoration. It also supplies the main-path live acceptance for the cleanup COM-identity handoff correction. It does not claim the harness automatically restored anything.

This RunId is distinct from earlier failed or temporary-snapshot runs. Preserve its persistent JSON/descriptor/txt and associated TEMP suite/case evidence. Exact VM build, PS minor, commit and completion timestamp are not visible and were not independently extracted. Ctrl+C, alternate terminal hosts, cancellation and every IO/crash fault point are not newly certified by this screenshot. See [persistent recovery plan](../../plans/DONE/resume-explorer-Task-5-persistent-snapshot-restore-guidance-plan.md) for remaining coverage.

## Smoke and manual Restore after the encoding correction (2026-11-04 client date)

The user supplied `codex-clipboard-3bca4b45-8f77-46ad-bb72-9c9119274d55.png` and `codex-clipboard-78d1b451-91d9-4ada-a2fc-f3a8991a398b.png` following the Recovery output-encoding correction. This records user-executed VM acceptance; the agent did not run the VM workflow or inspect the original JSON reports. Raw screenshots remain outside the repository.

| Item | Visible evidence / supported conclusion |
| --- | --- |
| Smoke result | Supervisor displays `測試結果: Passed`; launcher displays `Explorer smoke exit code: 0` |
| Persistent Snapshot | `%LOCALAPPDATA%\ResumeExplorer\Snapshots\BeforeSmoke\c56cde9dad6a40c489fb61b49143b788.json` |
| Recovery guidance | Full Restore command and matching `.restore.txt` path displayed; automatic restoration explicitly not performed |
| Manual Restore | Second screenshot executes the displayed command against the same Snapshot; report status `(Completed)` |
| Restore verification | `Verification: Complete`, `Total: 4`, `Verified: 4`, `Not verified: 0`, `All 4 items verified.` |
| Restore report | `%LOCALAPPDATA%\ResumeExplorer\Runs\5e761290a68449d19127f14fb30f14a2.json` |

This supports one successful VM smoke run and a subsequent manual Restore of the saved configuration. Under the reviewed success gate, smoke exit 0 requires both E01/E02 verification and cleanup to pass. The screenshots do not show individual case rows, offline baseline counts, active output encoding, exact VM runtime/build, or tested commit; none are inferred from local results or earlier screenshots. In particular, this does not independently establish that the temporary UTF-8 workaround was absent. Repeated reliability, other terminal hosts and the remaining failure matrix are not newly certified.

## Persistent recovery closeout (2026-11-04)

Core implementation and main-path acceptance are complete; the [plan](../../plans/DONE/resume-explorer-Task-5-persistent-snapshot-restore-guidance-plan.md) is archived in plans/DONE with its evidence and limitations. Closeout source review used local HEAD `a3586fc`; this is not a verified VM revision. The agent reran the offline baseline under ASCII in PowerShell 7.6.1: 39/17/23/49/13, 141 PASS, all exit 0, caller encoding preserved. No live Explorer operation was performed for closeout. Extended cancellation/terminal-host/fault-injection/repeatability coverage remains open in [Backlog](../../Backlog.md); archival does not certify it.

## Interrupted batch: recovery guidance retained (2026-11-04)

The user supplied `codex-clipboard-64c43541-ee16-4456-873e-33b331d9595d.png`. The screenshot shows `Run-ExplorerSmoke.cmd`, VM consent, five offline suites passing 39/17/23/49/13 (141 total, each exit 0), detection of two existing windows/four tabs, and selection of S. It then displays a persistent Snapshot and restore.txt for RunId `d45f6e278e5a4aa182338f71d81608a2`, followed by a final recovery summary with `程序異常結束／結果不明`, the same Snapshot and full Restore command. The terminal subsequently shows `Terminate batch job (Y/N)?`, answer N, and `^C` before returning to the prompt.

This supplies partial live evidence for F02: recovery guidance is retained during a batch interruption, with no false Passed summary. It does not identify the exact interruption point/signal sequence, prove the worker has exited, supply a final launcher exit code or case results, or show execution of Restore for this Snapshot. No claim is made that the full smoke passed, all test windows were cleaned up, or the entire Ctrl+C/terminal-host matrix is complete. Confirm the worker has stopped before acting on the recovery command. The source screenshot remains outside the repository; no live operation was performed by the agent.

## Multi-window close correction closeout (2026-11-04)

The [multi-window close plan](../../plans/DONE/resume-explorer-Task-5-multi-group-close-regression-plan.md) is Done for its core correction and main-path acceptance. Source review at local HEAD `002fb9f` confirmed the convergence, exact SC_CLOSE selector, fingerprint/scope gates, shared deadline, one-post invariant, and integration at startup/E01/E02 cleanup. The previously executed ASCII baseline remains applicable (141 PASS, all exit 0): no PowerShell source/test changes exist between `a3586fc` and this review HEAD. It was not rerun for this documentation closeout. A new STA load-only probe passed for the native helper/UIA assemblies without any Shell enumeration or window action.

The existing successful SC_CLOSE run and later successful persistent-recovery smoke support main-path live acceptance; no additional successful VM run or exact tested revision is invented. Remaining V01–V05 subcases and raw-artifact/runtime traceability are open in [Backlog](../../Backlog.md). The interrupted batch above is not counted as a successful close/cleanup or a consecutive reliability run. Archival certifies neither the entire matrix nor all Explorer hangs.

## Task-1 shared baseline: user integration acceptance (2026-11-04)

Task-1 subsequently passed closeout review at local HEAD `a96ae8c` and its [plan was archived as Done](../../plans/DONE/resume-explorer-Task-1-automated-tests-plan.md#16-結案-review-與歸檔2026-11-04). The agent reran the public offline entry (175 PASS, all exit 0) and checked its JSON/logs; the user-provided live evidence below was reused, with no additional GUI operation. The local review revision does not identify the tested VM revision.

The user supplied two screenshots after the Task-1 implementation and CMD launcher delivery:

- `codex-clipboard-8296da5a-f97d-4d90-b056-ffc008bacf9e.png`: executing `tests/Run-Tests.cmd`; seven suites report 39/17/23/49/13/18/16 (**175 PASS**), each raw exit 0, final Offline Passed / E2E NotRun (OfflineOnly), launcher exit 0, and a new offline evidence directory.
- `codex-clipboard-a75ae75c-e601-4cf6-826a-dc55f7800cc0.png`: final supervisor summary `測試結果: Passed`, `Explorer smoke exit code: 0`, persistent Snapshot `%LOCALAPPDATA%/ResumeExplorer/Snapshots/BeforeSmoke/a8e72945e09d4e7db05e06cf1c026def.json`, matching `.restore.txt`, and a complete PowerShell Restore command. The summary explicitly says automatic restoration was not performed.

Together these supply user-executed main-path integration acceptance following the new shared collector. Source review of the current success gate confirms that Passed requires the offline baseline, E01/E02 verification and cleanup, followed by supervisor validation of a Passed suite-result. Individual case rows and logs are not visible in the smoke screenshot; those steps are inferred from that gate, not independently inspected. Saving is supported by the displayed persistent Snapshot and recovery guidance.

The agent did not run the VM, inspect original JSON/logs, or execute the displayed Restore command. Exact tested revision, VM Windows build, PS minor, terminal product, case roots and completion timestamp are not shown. Local review HEAD `5ded85b` is not asserted to be the VM revision. The preceding offline screenshot and smoke screenshot are separate runs; their evidence IDs are not conflated. PS7.4.22 and extended repeatability/negative matrices remain unverified. The subsequent manual-Restore screenshot below supplies a result for this same Snapshot. Original screenshots and private raw paths remain outside the repository. This documentation update does not change code or require a further GUI run.
### Manual Restore of the Task-1 pre-smoke Snapshot (2026-11-04)

The user supplied `codex-clipboard-1b4477b1-2fd0-4edb-9e08-0e0714e9b697.png`. It shows execution of the displayed PowerShell Restore command against the same `BeforeSmoke/a8e72945e09d4e7db05e06cf1c026def.json` Snapshot from the preceding successful smoke run.

| Item | Visible evidence |
| --- | --- |
| Restore report | `%LOCALAPPDATA%/ResumeExplorer/Runs/1b28673b7c584dd6bd325582a530419d.json`, `(Completed)` |
| Verification | `Complete` |
| Items | Total 4, Verified 4, Not verified 0 |
| Final message | `All 4 items verified.` followed by the PowerShell prompt |

This supplies user-executed manual Restore acceptance for this saved configuration, in addition to the 175-case offline and smoke acceptance above. The agent did not perform Restore or inspect the original report. The screenshot does not display `$LASTEXITCODE`, so no raw Restore process exit is asserted. Existing runtime/revision and extended-matrix limitations remain unchanged. This update changes documentation only; no additional test run or commit was made.
