---
name: explorer-shell-hang-investigator
description: Investigate or reopen Windows File Explorer right-click/open/new-tab hangs using Process Explorer stacks, wait chains and Shell extension IPC. Use for resume-explorer Issue-6 (Closed/Mitigated; Google Drive drivefsext.dll suspected) on the personal Dell G15 PC, while keeping Issue-5 process counts separate.
---

# Explorer Shell Hang Investigator

1. Confirm machine/environment: the **Issue-6 Explorer Not Responding incident** happened on the user's personal **Dell G15**, not the company's VMware Horizon VDI.
2. Read repository-root `Backlog.md` **Issue-6 under Completed**, then `plans/resume-explorer-Issue-5-drivefs-shell-hang-rca.md` (legacy filename) and `references/issue-5-handoff.md`. **Issue-5** now refers only to the open, separate multi-Process/lifecycle investigation.
3. Respect status **Closed (Mitigated)**, not “root cause fixed.” Do not reopen or deliberately reproduce hangs without a genuine recurrence or new evidence.
4. State attribution accurately: **no evidence shows `resume-explorer` Capture/Restore/Restart caused the hang, and it is not an established bug of this program**. The historical stacks showed `drivefsext.dll → WaitNamedPipeW`, and Quit Google Drive was followed by Explorer recovery. This supports a Google Drive/Shell connection, **not** a proven exclusive root cause; a controlled experiment has not fully ruled out indirect script involvement.
5. On recurrence only, verify current Drive state, not historical PIDs (hung Explorer PID 44244, TIDs 89092 and 51124). With sync/work safe, collect a minimal Drive-off baseline, then optionally a Drive-on comparison of the same nonsensitive local-file right-click/open/navigation/new-tab actions. Stop at the first new hang and capture matching stacks/wait chains.
6. Interpret evidence conservatively: Wait Chain endpoints are not necessarily offenders; `Start Address` is not a Call Stack; `WaitNamedPipeW` does not identify the pipe server/timeout/root cause. Nearest-export symbols such as `DllInstall` / `uprv_getICUData_n4m` can mislead.
7. If further isolation is approved, change only one Google Drive Shell handler with a rollback plan. Never kill Explorer/threads, modify registry, stop active sync or make dumps automatically. **Do not change `resume-explorer` code until script-specific repro evidence appears.**
8. Append dated findings to the RCA and update Issue-6 status only from evidence. Keep Issue-5 process counts and personal PC/VDI observations separate; preserve pre-existing Git changes and run `git diff --check`. Do not commit unless requested.

For an offline summary, read `references/issue-5-handoff.md` (legacy filename).
