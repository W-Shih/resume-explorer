# Issue-4 — 同步 COM/UIA 操作超時 RCA 與修復計畫

日期：2026-11-01；狀態：待實作／待驗證；**本次僅拆分文件，不改 Restore 程式碼**。

來源案例：`02e5f26b61da4a1ba503bea37d15323f.json`。真實 Report 含使用者路徑，不得提交公開 repo。

對應：`Backlog.md` Issue-4（P1）。

## 已知事實與待證實假設

案例為 18 items：13 `Verified`、1 `OutcomeUnknown / NavigationTimeout`、4 `NotAttempted`，皆位於 Group 6 的未驗證序列。Tab 3 已嘗試 Invoke 與 Navigate，項目歷時 28,545 ms。Navigation 只有一筆 observation，標示 elapsed 15,813 ms、`RawCount=68`、`UniqueCount=68`、`Reliable=True`；該觀測的 Views 中包含要求的目標路徑，但**不能僅憑路徑存在就認定新候選 Tab identity 已被穩定驗證**。

這份 JSON 精確大小為 **3,002,321 bytes**（約 **3.00 MB / 2.86 MiB**），包含 **18 items、87 筆 Diagnostics.Samples、共 5,119 筆儲存的 Views**。這是「全域清單反覆快照」可能造成膨脹的強烈證據，但完整的位元組占比仍需精確量測，不能直接宣稱所有大小皆來自 Views。

目前 `Get-ExplorerObservation()` 會透過 `Shell.Application.Windows()` 枚舉全域 Shell 視窗／分頁，再記錄 Path、HWND、fingerprint、identity 等資訊；`Add-ObservationDiagnostic()` 會在每次 sample 保存 Views 與 Errors。觀測呼叫屬同步執行，現有輪詢 deadline **不會強制中斷一個卡住的 COM/UIA call**。目前尚未證明是滑鼠切焦點，或「單個 Explorer 視窗 Tab 太多」，造成這次超時。RawCount=68 也不等於已確認有 68 個單一視窗內的 Tabs。

## 同步操作／NavigationTimeout RCA 與修復方向

### 1 Phase 1 — 效能儀表化（優先）

在不改 restore 行為的前提下量測：`ObserveStartedAt`、`ObserveDurationMs`、`ShellWindowsEnumerateDurationMs`、每筆慢的 `FullName/HWND/Fingerprint/Identity/Path` 階段、`ObservedViewCount`、`DeadlineRemainingBefore/After`、`DeadlineOverrunMs`。避免預設持久化全部路徑：慢步驟以 stage、耗時、HRESULT、目標 HWND／索引等診斷表示，敏感資訊放在 opt-in 詳細模式。

特別區分「observation 開始時已有超時」與「同步 COM call 在 deadline 之內開始、卻於 deadline 之後才返回」；保留純 monotonic stopwatch。由單一 observation 的耗時與前後 timestamps 證明阻塞點，而非由 Sample 的 elapsed label 直接推斷完整函式耗時。

### 2 Phase 2 — 降低同步工作量

先用 profiler/trace 確認是否反覆枚舉全域 68 個 Shell 物件或某一個 COM property 存取特慢。研究可否以 target HWND 篩選後減少不必要的 Path/Fingerprint 讀取，但不能降低「全域觀測完整性」及 duplicate／candidate identity 的安全性。任何 target-aware fast path 必須證明可以區分同一個目標視窗所有 baseline/new tabs，並且遇到未完整觀測仍保守停止。測試高 Tab 數、多個 Explorer 視窗、共享路徑及 slow COM property。

### 3 Phase 3 — 有界同步呼叫隔離（只在證據支持時）

如果 COM call 長時間阻塞，僅把 `NavigationTimeoutSeconds` 從 10 調到 20/30 秒只能延後失敗；無法保證有界等待。研究獨立 process/STA worker 與通訊 deadline、生命週期及停止協定；若 caller 超時，對曾經發出的副作用（Invoke/Navigate）須維持 `OutcomeUnknown`，不可在未確認前自動重發。不得使用 `Thread.Abort` 等任意中斷方式，亦不得為了取消 worker 而殺死 `explorer.exe`。

### 4 Acceptance

- 可準確呈現每次 Observe 的實際耗時與 deadline overshoot；長 COM call 不會被誤判成只發生很多次 polling。
- 高負載測試包含全域 20/50/100+ 個 shell view（測試參數，非效能保證），並保留 600 ms 穩定驗證與候選單一性。
- 不再因單純 A/B 焦點切換而錯選 Tab；C/D/E 若確定有歧義仍安全中止。
- 恢復成功率與耗時需以基準測試量化；不承諾在 Windows COM 不合作時實現硬性 wall-clock SLA。
- 不改原始 Group/Item 索引、checkpoint、single Invoke/Navigate 及 Retry 風險控制。



## 相關工作與共通保護

- 保留 Issue-2 的單次 Invoke／Navigate、Tab identity、原子 checkpoint、OutcomeUnknown 與 PreviewRetry／Retry 安全規則。
- 在隔離 Windows 測試環境執行 E2E，不直接於使用中的 Explorer 壓測；完成後更新 Backlog、README 與驗證紀錄。

- 焦點行為的專門測試見 `resume-explorer-Issue-3-focus-independence-plan.md`；Compact Diagnostics 及 Schema 變更由 Feature Request-6 負責。
