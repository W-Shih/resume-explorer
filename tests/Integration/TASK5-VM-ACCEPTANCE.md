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

The detailed follow-up [plan](../../plans/resume-explorer-Task-5-multi-group-close-regression-plan.md) records remaining extended-matrix gaps: three consecutive two-window runs, explicit close-without-save/cancel, larger/duplicate-path groups, zero-existing-window startup and live negative cases are not all established by this screenshot. **The main automatic smoke passed; the extended matrix is not declared fully complete.** No code or tests changed as part of recording this result, so no new GUI or unit-test run is required for this documentation update.
