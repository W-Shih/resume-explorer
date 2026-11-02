---
name: explorer-shell-hang-investigator
description: Investigate Windows File Explorer right-click/open/new-tab hangs via Process Explorer stacks, wait chains and Shell extension IPC; resume resume-explorer Issue-5 involving Google Drive drivefsext.dll and update RCA safely on the personal Dell G15 PC.
---

# Explorer Shell Hang Investigator

1. Confirm machine/environment: Issue-5 refers to the user's **personal Dell G15**, not the company's VMware Horizon VDI.
2. Read `E:\_projects\tools\scripts\resume-explorer\plans\resume-explorer-Issue-5-drivefs-shell-hang-rca.md` and `Backlog.md` Issue-5 first. Treat them as the authoritative and dated handoff.
3. Confirm current Google Drive state (quit/restarted), not historical PIDs. Historical hung Explorer PID 44244, TIDs 89092 and 51124 must NOT be reused as active IDs.
4. Distinguish observed facts from hypotheses. Historical Threads → Stack showed `drivefsext.dll → WaitNamedPipeW`; Quit Drive caused the prior hung Explorer to recover. The subsequent new This PC tab took 3–5 minutes, after which open/navigation were normal. **No confirmed root cause, no recorded Drive restart/re-challenge, no evidence resume-explorer itself caused this.**
5. Follow safe A/B: Drive quit → baseline of a few non-sensitive local-file right-click/open/navigation/new-tab operations; Drive restarted only when sync/work safe → repeat identical operations and record latency/PID. If hangs return, stop repeated repro attempts, collect Process Explorer stacks and Task Manager Analyze Wait Chain.
6. Wait chain ends are not automatically offenders; `Start Address` is not a Call Stack. `WaitNamedPipeW` identifies a named-pipe wait, not the server/timeout cause. Nearest-export symbols such as `DllInstall` / `uprv_getICUData_n4m` may be misleading.
7. If still needed, isolate only the Google Drive context-menu handler with an explicit rollback and user approval; never kill Explorer/threads, modify registry, stop active sync, or make dumps automatically.
8. Append dated evidence to the plan and update Backlog summary; keep personal PC and VDI evidence separate. Preserve pre-existing Git modifications and run `git diff --check`. Do not commit unless requested.

For an offline summary, read `references/issue-5-handoff.md`.
