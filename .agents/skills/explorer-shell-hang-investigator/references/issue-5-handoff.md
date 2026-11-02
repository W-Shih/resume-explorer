# Issue-5 handoff (2026-11-02)

Authoritative ongoing RCA: `plans/resume-explorer-Issue-5-drivefs-shell-hang-rca.md` and `Backlog.md` Issue-5 in `E:\_projects\tools\scripts\resume-explorer`.

- Personal PC (Dell G15), **not VMware Horizon VDI**.
- Right-clicking a file alone caused its Explorer process to become Not Responding; other explorer.exe instances were usable. Double-click PDF/MP4 triggered it too; reader/player File > Open worked.
- Historical hung Explorer PID 44244, 48 threads. Wait chains included `83032 → 77596 → 89092` and `48344 → 10152 → 51124`.
- TIDs **89092** and **51124** had matching stacks: `drivefsext.dll → KERNELBASE!WaitNamedPipeW → ntdll!ZwFsControlFile`; strong association with Google Drive Shell extension; endpoint/server/root cause unknown.
- Two GoogleDriveFS.exe processes 33000 (started 2026-10-29) and child 85840 (started 2026-11-01), both Session 1, matching Explorer session. Installed executable under Drive File Stream/133.0.2.0.
- After user clicked Quit Google Drive from notification area, original hung Explorer recovered. New This PC tab displayed “正在處理...” for **3–5 minutes**, then open/navigation worked normally. Exact reason for delayed recovery unknown.
- **Still untested**: Drive restart and re-challenge, sustained stability while Drive quit; whether right-click hang and new-tab delay have same cause. No proof of any `resume-explorer` regression.
- Next: observe baseline with Drive off, then carefully retry with Drive on using a few same local files; record per-operation latency and new PID; stop on first hang; update RCA and Backlog.
