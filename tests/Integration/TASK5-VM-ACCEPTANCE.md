# Task-5 VM smoke acceptance — user-provided evidence

**Decision: Task-5 Closed / Completed, 2026-11-02 (America/Tijuana).** The user ran the guided one-click workflow in a Windows 11 test VM and supplied the final console screenshots. This records user-executed acceptance, not an agent-run or independently replayed GUI test.

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
