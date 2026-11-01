# Backlog

## Issues

### Issue-1

這種路徑沒有打開 "H:\fake-path\dummy.zip"

### Issue-2

```txt
PS C:\Projects\resume-explorer
λ & .\resume-explorer.ps1 -Action Restore
Group 1, HWND 1001 : C:\Users\Example\Documents\Project
  Requested new tab: C:\Users\Example\Documents\Project\Notes
  Requested new tab: C:\Users\Example\Documents\Project\Reports
  Requested new tab: D:\Data\Downloads
  Requested new tab: C:\Tools\ProcessViewer
Group 2, HWND 1002 : D:\Work\Learning\AI-Coding\Course\Module-1
WARNING: Group 2: Multiple new tabs detected; cannot safely choose one. Remaining tabs in this group skipped.
Group 3, HWND 1003 : D:\Personal\Projects\2026
  Requested new tab: D:\Personal\Projects\2025
  Requested new tab: D:\Personal\Projects\2027\Preparation
  Requested new tab: D:\Data\Downloads\Reference
Group 4, HWND 1004 : C:\Users\Example\Downloads\Shared\Work
  Requested new tab: C:\Users\Example\Downloads\Shared\Archive
Group 5, HWND 1005 : D:\Work\Projects\Design\Current
Group 6, HWND 1006 : C:\Projects\Tools\Output
Restore attempted. Inspect resulting tabs before considering a restart workflow.
```

**問題與目標（意圖，不是強制實作規格）**

Group 2 因為 `Multiple new tabs detected`，使該 Group 後續 Tabs 被跳過。希望提升對 Explorer 暫時性狀態更新延遲／觀測錯誤的容錯能力，同時避免將路徑導覽到錯誤的分頁。

**建議設計方向（初始值可依實測調整）**

- 每個新增 Tab **最多送出一次** AddButton / Invoke；後續只重新觀測，不可重複建立或猜選候選 Tab。
- 建議以**偵測總期限**取代固定 `1 + 3` 次為硬性停止條件：初始 `DetectionTimeoutSeconds = 15`，正常觀測間隔約 `200 ms`。針對暫時性讀取錯誤，可用 `200 → 400 → 800 ms` 的有限退避（持續錯誤時最高維持 800 ms），直到恢復或到期；不因第 3 次仍失敗就提前放棄。
- 真正有多個不同候選／身分歧義、目標視窗失效等不可安全處理情況，可**提前停止**該 Group；延長等待不能當成安全識別的證據。
- 如果該 Group 最終仍未完成，須記錄**目前失敗或結果不明的項目**及**尚未嘗試的項目**，讓使用者之後指定目標 Explorer 視窗與項目手動補做；其他正常 Group 照常處理。
- 15 秒只是**單次新增 Tab 的觀測期限**，不是整次 Restore 的總期限；同步 COM/UIA 呼叫本身若卡住，需另外評估隔離方案。

上述數值並非硬性需求；以**安全性、成功率、等待時間及實測證據**決定最終參數。詳細策略與驗收見 [`plans/resume-explorer-Issue-2-fix-plan.md`](plans/resume-explorer-Issue-2-fix-plan.md)。

**2026-11-01 實作進度：候選版，Issue 保持開啟**

- 後續 regression 修復：報告 `535b092885594426af03bded40354d85` 記錄 6 次視窗建立、12 次分頁 Invoke，18 項 Verified；引用的診斷對話確認 6 個新 HWND 都不可見。建立視窗時誤用了 `-WindowStyle Hidden`，現改為明確 `Normal`，並加入直接攔截 production adapter 啟動參數的回歸測試。原有 baseline／候選驗證／checkpoint 不變；舊的隱藏視窗不自動操作。

- 已加入獨立 core、可信 baseline、單次 Invoke、15 秒共享觀測 deadline、200 ms polling、200/400/800 ms capped backoff、候選歷史及同身分導覽驗證。
- 已加入原子 checkpoint、原始 Group / Item 索引、完整逐項狀態與 PreviewRetry / Retry；補做明確選擇 HWND 及項目，檢查預覽指紋及同家族子報告。
- 自動驗證與尚未驗收項目見 `ISSUE2-VALIDATION.md`；尚無原 Group 2 問題環境的 trace，不能判定 baseline 遺漏、重複列、物件更換或真正併發何者是實際根因。
- 尚待原 Horizon VDI 實機矩陣與 20 次多 Group 還原；版本暫留 `0.1.0-beta.1+issue2`，不宣告 beta.2 發布。沒有自動 commit，修復 commit 待審閱後建立。

## Feature Requests

### Feature Request-1

當執行 `& .\resume-explorer.ps1 -Action Restore` 時，希望在背景還原 Explorer 視窗與標籤頁，不顯示或彈出 Explorer 視窗、不將其帶到前景，也不搶走目前使用中應用程式的焦點，以免打斷使用者操作。

此需求針對 Explorer 視窗本身的顯示與焦點行為，不是僅隱藏 PowerShell／Console 視窗。

先記錄期望行為，不預設實作方式，也不因技術難度預先縮減需求。可行性與開發成本留待後續評估；若無法可靠達成或成本不合理，可記錄原因並將此需求標記為 Rejected。

### Feature Request-2

詢問是否將執行檔加入系統 PATH, 以便在任何目錄下都可以直接執行 `resume-explorer.ps1` 而不需要指定完整路徑

### Feature Request-3

當執行 Capture 功能時, 目前只會保留最後一次的標籤頁組合, 並會覆蓋掉之前的組合. 建議至少提供 2-3 個組合的保留, 以便使用者可以回溯到之前的標籤頁組合, 而不會因為覆蓋而失去之前的組合.

### Feature Request-4

將此功能整合進其他專案 `restart-win-explorer-scripts` 和 `restart-windows-taskbar`, 以便在重啟 Windows Explorer 或 Windows Taskbar 時, 可以自動恢復之前的標籤頁組合, 提升使用者體驗. 但不是單純複製貼上 src code, 注意 DRY 原則和 SRP 原則, 需要將共用的功能抽象化成模組或函式庫, 以便在不同專案中重複使用, 並且方便維護和更新.

### Feature Request-5

是否有實作圖形化使用者介面（GUI）的需求？目前工具透過 PowerShell 參數執行 Capture、Preview 與 Restore；可評估是否需要 GUI 來檢視 Snapshot、選擇操作或呈現執行結果，再依使用情境決定是否實作。

## Tasks

### Task-1

為 `resume-explorer.ps1` 建立自動化測試，涵蓋 Snapshot 讀寫與驗證等可單元測試的邏輯；並評估在支援的 Windows 環境中加入端對端測試，驗證 Explorer 視窗與 Tabs 的還原行為。

### Task-2

若開起的路徑或檔案不存在，應記錄警告訊息，並跳過該路徑或檔案。不需要中斷整個還原流程。
