# Issue-6 — Explorer Hang / Google Drive Shell Extension RCA

- **Status (2026-11-02):** **Closed (Mitigated)** in [`Backlog.md`](../../Backlog.md), Issue-6 under Completed. The observed Explorer hang recovered after Quit Google Drive; **root cause has not been confirmed and no product/code fix is claimed**. The earlier P1/in-progress classification described the incident *before* it was split from Issue-5.
- **Scope:** Windows File Explorer right-click / open / tab-loading hang on the user's **personal Windows PC (Dell-G15-Ryzen)**, **not** the VMware Horizon VDI. Archived in `plans/DONE/` as Issue-6's historical RCA and reopen playbook; `Closed (Mitigated)` does not mean permanent resolution.
- **Causal attribution / ownership:** **There is no evidence showing that `resume-explorer` (Capture, Restore or Restart) caused this `Not Responding` incident. Do not label it as a confirmed `resume-explorer` defect.** The evidence instead points to a `drivefsext.dll` Named Pipe wait and recovery after quitting Google Drive, making Google Drive/Windows Shell integration the *leading suspect*, not a proven exclusive root cause. Without a controlled script before/after experiment, one cannot completely exclude an indirect contribution. Do **not** modify Restore logic without a specific reproducible correlation.
- **Related but separate:** [`Backlog.md`](../../Backlog.md) **Issue-5** remains **Open / P2** and tracks only unexpected Explorer process counts/lifecycle; this incident's recovery does not close Issue-5.
- **Reopen gate:** Only if the right-click/open hang recurs, or if fresh evidence specifically implicates `resume-explorer`, resume the low-risk A/B steps below. Do not trigger a new hang merely to justify closing or reopening a mitigated incident.
- **Reusable workflow:** [`../../.agents/skills/explorer-shell-hang-investigator/SKILL.md`](../../.agents/skills/explorer-shell-hang-investigator/SKILL.md).

## 1. Verified observations (not hypotheses)

| Evidence | Observation | Interpretation / limit |
| --- | --- | --- |
| 2026-11-01 | Explorer sluggish after restart; a separate observation showed 9 explorer.exe processes, one Responding=False. A prior taskkill reported 38 PIDs. | Process counts alone do not establish a leak or cause. |
| 2026-11-02, initial symptom | Explorer window becomes Not Responding on file double-click (PDF / MP4); later **right-click alone** triggers the hang, before the context menu/Open command. | The default PDF/video app is not the hung process. |
| Comparison | File > Open from an already open PDF reader or media player works normally. | Favors an Explorer/Shell-specific path, not file decoding. |
| Process isolation | Only the operated-on Explorer process/window hangs; other Explorer processes remain usable. Example hung PID **44244**, 48 threads. | Snapshot PID only; does not exclude shared third-party handlers. |
| Process Explorer | TID **71372** stack includes `win32u!NtUserMsgWaitForMultipleObjectsEx` and `explorerframe.dll`. TID **79848** shows an idle thread-pool stack. | Neither alone proves a deadlock or identifies the UI owner. |
| Task Manager → Analyze wait chain | Examples: `83032 → 77596 → 89092`; `65120 → 77596 → 89092`; `48344 → 10152 → 51124`; also `10152 → 51124`. | Chains identify dependencies, not the definitive root cause. |
| Process Explorer → Threads → Stack | TIDs **89092** and **51124** show effectively the same `drivefsext.dll` call chain ending in `KERNELBASE!WaitNamedPipeW` and `ntdll!ZwFsControlFile`. | Direct evidence that DriveFS extension threads are waiting for Named Pipe availability; not proof of which server/endpoint failed or why. |
| Process query | `GoogleDriveFS.exe` PIDs **33000** (parent 15584, started 2026-10-29 06:25:49) and **85840** (child of 33000, started 2026-11-01 12:01:32); hung `explorer.exe` PID **44244**, parent 2140, started 2026-11-02 06:24:44. All **SessionId 1**. | Same session rules out a cross-session mismatch in this sample; two Drive processes are not by themselves abnormal. |
| Installed Drive executable | `C:\Program Files\Google\Drive File Stream\133.0.2.0\GoogleDriveFS.exe` for both observed Drive processes. | Does not establish the version or signature of loaded `drivefsext.dll`; check module details if needed. |
| **Intervention: Quit Google Drive from tray** | Previously hung Explorer recovered **without force-killing Explorer**. Opening a new Explorer tab still took ~**3–5 minutes** and showed `This PC / 正在處理...`. After that tab finished loading, ordinary open/navigation operations were reported normal and acceptably responsive. | Strong temporal intervention evidence supporting a Google Drive integration/IPC connection. **Do not claim** an exact timeout mechanism, that right-click was individually retested, or that the long tab load shares the same root cause. |

### Representative stack evidence

Both **89092** and **51124**, captured while PID 44244 was hung:

```text
ntdll.dll!ZwFsControlFile+0x14
KERNELBASE.dll!WaitNamedPipeW+0x215
drivefsext.dll!uprv_getICUData_n4m+0x1dcad1   (nearest symbol + offset)
drivefsext.dll!...                          (multiple internal frames)
drivefsext.dll!jump_fcontext+0xef063       (nearest symbol + offset)
KERNEL32.DLL!BaseThreadInitThunk
ntdll.dll!RtlUserThreadStart
```

The `uprv_getICUData_n4m` / `DllInstall` / `jump_fcontext` symbols can be nearest available exports, not real private function names. Never infer an ICU failure or DLL-install action from them. `WaitNamedPipeW` waits for an available Named Pipe instance; this snapshot does not identify the pipe name, server process, retry count, timeout, or deadlock.

## 2. Current interpretation and open questions

**Project causality / fault classification:** No observed reproduction, before/after test or recorded causal chain ties this hang to `resume-explorer` Capture, Restore or Restart. **There is currently no evidence that this program caused the incident; therefore it must not be triaged as a confirmed `resume-explorer` defect.** This is a lack of supporting evidence, **not** proof of impossibility or an exhaustive exclusion test. Do not assign a script fix without new script-specific evidence.

**Leading hypothesis (medium-high confidence as an *association*, not confirmed RCA):**
A Google Drive for desktop Explorer Shell extension (`drivefsext.dll`) participates in an IPC/Named Pipe wait, potentially blocking right-click context-menu processing and other Explorer actions. Quitting Drive was followed by recovery of the previously hung process.

**Still unknown:**
- Whether the same problem recurs after Google Drive is restarted; **no successful re-challenge / ABAB experiment yet**.
- Whether the initially slow new `This PC` tab is the same blocked pathway or separate namespace/virtual-drive enumeration, cache, or timeout behavior.
- Which named pipe and server endpoint are involved; why it is unavailable/busy; whether DriveFS, its Shell handler, another dependency or an external condition is primary.
- Whether right-click, file open, new-tab and navigation all remain stable while Drive stays closed for an extended observation period.
- Whether `resume-explorer` has any indirect contribution: no controlled comparison of script operations before/after the hang has been recorded, and no available evidence implicates the script. This open question does **not** establish that the script contributed.

**Avoid these conclusions:** confirmed Google Drive bug; Explorer-wide deadlock; memory/process leak from counts; fault in PDF/MP4 applications; fixed retry timeout of 3–5 minutes; `resume-explorer` root cause; **proof that `resume-explorer` is categorically incapable of contributing**; VDI-specific fault.

## 3. If Issue-6 recurs: prioritized, low-risk plan

1. **Confirm a real recurrence and avoid repeat work.** Read this plan and **Issue-6 under Completed** in [`Backlog.md`](../../Backlog.md); keep unrelated **Issue-5 process counts** separate. If the hang has not recurred, leave Issue-6 Closed (Mitigated) and do not run potentially disruptive experiments merely to close its RCA. If new symptoms appear, record whether Drive was restarted since the previous observation; preserve newer evidence. PIDs/TIDs here are historical, not active identifiers.
2. **Baseline while Drive is quit (A).** On the personal PC, confirm Drive process/tray state (read only). For a *small number* of non-sensitive **local** files, note right-click menu latency, double-click/open latency, navigation and new-tab/`This PC` load time. Avoid repeated hangs; use a normally operating Explorer process when possible. Log actual times and whether the same tab vs new tab was used.
3. **Restart Drive (B) only when user is ready.** Ensure file sync/work is safe, launch from Start and verify Drive has initialized; note process IDs/start times. Recheck exactly the same small set of operations and local paths. Stop the experiment on a reproduced hang rather than repeatedly causing more; do not assert success from a single quick operation.
4. **Observe outcome.**
   - A stable, B hangs: markedly strengthens Drive integration causality; Quit Drive again as a reversible workaround if needed, note whether recovery is immediate or delayed.
   - A stable, B stable: may have been a transient IPC state; keep Issue-6 Closed (Mitigated), revisit after real recurrence rather than inventing repros.
   - A hangs, B hangs: reassess Shell extensions/Windows Explorer independently of Drive.
   - New tab slow but context menu normal: open a **separate sub-investigation** of `This PC`/new-tab initialization vs. right-click, with distinct reproduction metrics.
5. **Only if needed: stronger isolation.** If safe and approved, use ShellExView/Autoruns to locate the *single* Google Drive context-menu handler, record current setting, and temporarily disable it (restore afterward); this often requires reloading Explorer. Do not indiscriminately disable all handlers or restart/terminate every Explorer process. Alternative: event logs, Process Explorer module paths and symbols, then opt-in dump analysis if still inconclusive.
6. **Update evidence and tracker.** Append dated results below; change status only on the evidence. Keep conclusions conditional and ensure VDI case evidence remains separate.

### Repeatable observation log (copy for next run)

| Local time | Drive state/PIDs | Explorer PID | Action & target type | Result/latency | Evidence | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| TBD | off/on, PIDs | new PID | right-click local test file | normal/hang, seconds | screenshot/log | one trial |

### Optional read-only commands

```powershell
Get-CimInstance Win32_Process -Filter "Name='GoogleDriveFS.exe'" |
  Select-Object Name, ProcessId, ParentProcessId, SessionId, CreationDate
Get-Process explorer -ErrorAction SilentlyContinue |
  Select-Object Id, ProcessName, Responding, StartTime, CPU
```

To inspect a new hang: Process Explorer → hung Explorer PID → Properties → Threads → select relevant TID → **Stack** / **Refresh**; Task Manager → Details → PID → **Analyze wait chain**. Save screenshots/times; `Threads` list and Start Address are not Call Stacks. For a full process dump, get explicit consent, consider memory/privacy and available space, and redact before sharing.

## 4. Decision and safety gates

- **Issue-6 is Closed (Mitigated), not root-cause Resolved.** The user's reported recovery supports operational closure, not a code fix. Reopen only if a real hang recurs or new substantive evidence demands it; then reassess severity (P1 if materially disruptive). Issue-5 remains a **separate Open/P2** process-lifecycle investigation. A future permanent resolution claim requires controlled evidence and acceptance criteria.
- **No destructive remediation by default:** no `taskkill /f /im explorer.exe`, no thread kill/suspend, no Registry edits, no mass shell-handler disable, no forced Drive quit when active sync/work is at risk.
- Document changes must not silently alter `resume-explorer.ps1` or `resume-explorer.core.ps1`. If subsequent evidence implicates the script, create a separate, testable reproduction and change proposal.
- This incident happened on the **personal** Dell G15. The repo's Windows 11/Horizon VDI observations relate to other testing; do not merge environments or infer VDI-specific causes.
- **Next check-point question:** Has Google Drive been restarted? If yes, did right-click/open/new-tab slowdowns recur, and after how long?

## 5. New findings / validation log

- **2026-11-02:** Documented post-Quit recovery, historical wait chains, Drive process tree and the unresolved 3–5-minute new-tab delay. Drive restart outcome **pending / not recorded**.
- **2026-11-02 (backlog split / attribution clarification):** This event is tracked as **Issue-6 Closed (Mitigated)**, separate from **Issue-5 Open/P2** process counts. **No evidence attributes the `Not Responding` incident to `resume-explorer`; Google Drive/Shell IPC is the leading but unconfirmed suspect.** Lack of evidence is not an absolute exclusion, and no script changes are warranted on this incident alone.
