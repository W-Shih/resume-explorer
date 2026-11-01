# Backlog

## Priority convention

- **P0 — Critical:** 資料遺失、安全性重大缺陷或核心功能完全不可用，必須立即處理。目前沒有已確認的 P0。
- **P1 — High:** 已觀察到的核心可靠性問題、顯著效能／資源成本，或支撐後續修復的必要測試。
- **P2 — Medium:** 有價值但非阻斷性的功能缺口、使用體驗改善與整合需求。
- **P3 — Low:** 可選的便利性與擴充功能，待較高優先級項目完成再評估。

優先級表示**目前的建議處理順序**，不代表排程承諾；必要時依重現率、影響範圍及實測證據重新調整。`Done`／`Closed` 是狀態，不是優先級。

## Issues

### Issue-1 — P2

這種路徑沒有打開 "H:\fake-path\dummy.zip"

### Issue-2 — Closed (implementation complete; live acceptance tracked separately; priority N/A)

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

上述數值並非硬性需求；以**安全性、成功率、等待時間及實測證據**決定最終參數。詳細策略與驗收見 [`plans/DONE/resume-explorer-Issue-2-fix-plan.md`](plans/DONE/resume-explorer-Issue-2-fix-plan.md)。

**2026-11-01 結案紀錄：核心修復已實作，Issue-2 Closed；未完成的實機驗收仍如實記錄於 `ISSUE2-VALIDATION.md`。**

- 後續 regression 修復：報告 `535b092885594426af03bded40354d85` 記錄 6 次視窗建立、12 次分頁 Invoke，18 項 Verified；引用的診斷對話確認 6 個新 HWND 都不可見。建立視窗時誤用了 `-WindowStyle Hidden`，現改為明確 `Normal`，並加入直接攔截 production adapter 啟動參數的回歸測試。原有 baseline／候選驗證／checkpoint 不變；舊的隱藏視窗不自動操作。

- 已加入獨立 core、可信 baseline、單次 Invoke、15 秒共享觀測 deadline、200 ms polling、200/400/800 ms capped backoff、候選歷史及同身分導覽驗證。
- 已加入原子 checkpoint、原始 Group / Item 索引、完整逐項狀態與 PreviewRetry / Retry；補做明確選擇 HWND 及項目，檢查預覽指紋及同家族子報告。
- 自動驗證與尚未驗收項目見 `ISSUE2-VALIDATION.md`；尚無原 Group 2 問題環境的 trace，不能判定 baseline 遺漏、重複列、物件更換或真正併發何者是實際根因。
- 原 Horizon VDI 實機矩陣、20 次多 Group 還原與根因歸因尚未完成；此處的 Closed 僅代表 Issue-2 核心修復已實作，不代表完成全部發布驗收或宣告 beta.2。後續同步超時／焦點互動與 Report 大小另由 Issue-3、Issue-4、Feature Request-6 追蹤。

### Issue-3 — P2 — Restore 不應依賴滑鼠焦點／前景視窗（待驗證）

- **預期行為**：Restore 期間使用者點擊 Chrome、Visual Studio 等其他應用程式，或將 Explorer 切至背景，不應因此導覽錯誤 Tab、失去已確認的 Tab identity 或錯誤中止。這是**互動容錯性**，與 Feature Request-1 的「不顯示、不搶焦點」是兩個不同需求。
- **風險界線**：使用者對**正在還原的目標 Explorer** 手動新增、關閉、切換 Tabs 或關閉視窗，可能改變 UIA／COM 可觀測狀態；工具仍應保守停止，而不是猜選 Tab。是否連單純切換同視窗的 active Tab 都安全，需實機測試驗證，不預先宣稱。
- **調查及驗收**：加入前景應用切換、其他 Explorer 視窗切換、目標 Explorer 手動操作等分離測試；比較每次觀測的 HWND、PID、Identity、Path 與耗時，釐清焦點切換是否造成異常。不可只因時間上相近就歸因於滑鼠點擊。
- 詳細方案：[`plans/resume-explorer-restore-reliability-and-report-size-plan.md`](plans/resume-explorer-restore-reliability-and-report-size-plan.md)。

### Issue-4 — P1 — 同步 COM/UIA 呼叫超過 Restore deadline（待 RCA）

- **實際證據**：2026-11-01 的 18-item Restore 有 13 Verified、1 OutcomeUnknown（Group 6 / Tab 3，`NavigationTimeout`）、4 NotAttempted。該項目共耗時 28,545 ms；Navigation 僅有一筆觀測，時間標記 15,813 ms，`RawCount=68`、`UniqueCount=68`，該觀測包含目標路徑，但尚不足以確認指定候選 identity 持續穩定。
- **原因未定**：全域 Shell COM 列舉／單一物件變慢、Explorer 負載、焦點／Tab 互動或同步呼叫阻塞皆仍是假設。現有 deadline 只限制輪詢邊界，**無法中止正在執行的同步 COM/UIA 呼叫**。
- **修復方向**：先量測每次 Observe 的 wall-clock duration、階段、deadline overshoot、列舉數量與慢呼叫位置；再比較減少不必要觀測、target-aware 快速路徑及具安全隔離的 worker 設計。不應僅將 10 秒調高，或以直接殺執行緒的方式中止有副作用的 COM 呼叫。
- **驗收**：在高 Tab 數、慢 VDI、同步阻塞與視窗互動下維持 identity safety、checkpoint 及有限的可觀測 deadline 語意；不能新增重複 Invoke／Navigate。
- 詳細方案同上。

## Feature Requests

### Feature Request-6 — P1 — 精簡 JSON Report 與可控診斷資訊（待實作）

- **實際證據**：同一份 2026-11-01 Report 的大小為 **3,002,321 bytes**（約 3.00 MB／2.86 MiB），僅 18 Items、87 個 Diagnostics.Samples，卻包含 **5,119 筆儲存的 View 記錄**，高度重複保存全域 Shell 觀測。
- **期望**：預設 Report 應保有 Run／Item 結果、ReasonCode、必要的事件時間與 Retry 安全依據，但不應每次 polling 都持久化全域全部 Explorer Views／Fingerprint。詳細 trace 應可透過明確指定的診斷模式取得，並設容量與樣本上限。
- **方案**：調查容量構成，優先改為每次觀測的精簡統計、階段摘要與異常時的有限樣本；必要時允許 opt-in 詳細 trace、大小上限與截斷計數，保持事故可診斷性。壓縮／minify 可作輔助，但不可取代去除冗餘資料。
- **相容性**：保留現有 ReportPath、原始 Group/Item、Status、ReasonCode、Run family 關係及 Retry 判斷；若改 Schema 須有明確版本策略與舊報告讀取測試。不能為縮小 Report 犧牲 crash checkpoint 或不明結果的安全保護。
- 詳細方案：[`plans/resume-explorer-restore-reliability-and-report-size-plan.md`](plans/resume-explorer-restore-reliability-and-report-size-plan.md)。



### Restore Result Summary & Unverified Item Diagnostics — Done (priority N/A; 2026-11-01)

- Restore／Retry 結束時顯示 Total、Verified、Not verified 與 Complete／Partial／Interrupted／Empty；列出全部非 Verified 的原始 Group／Tab、完整路徑、Status 及有值的 ReasonCode。
- 未驗證項目使用 native Warning stream，附安全引用的完整 PreviewRetry 指令；不自動執行補做，不改既有 JSON Schema、checkpoint、例外或 Restore／Retry 安全規則。
- 既有 39 項回歸與新增 17 項摘要離線測試通過，詳見 `ISSUE2-VALIDATION.md`。本次僅改善結果呈現，Issue-2／可見性實機驗收仍未完成。

### Feature Request-1 — P2

當執行 `& .\resume-explorer.ps1 -Action Restore` 時，希望在背景還原 Explorer 視窗與標籤頁，不顯示或彈出 Explorer 視窗、不將其帶到前景，也不搶走目前使用中應用程式的焦點，以免打斷使用者操作。

此需求針對 Explorer 視窗本身的顯示與焦點行為，不是僅隱藏 PowerShell／Console 視窗。

先記錄期望行為，不預設實作方式，也不因技術難度預先縮減需求。可行性與開發成本留待後續評估；若無法可靠達成或成本不合理，可記錄原因並將此需求標記為 Rejected。

### Feature Request-2 — P3

詢問是否將執行檔加入系統 PATH, 以便在任何目錄下都可以直接執行 `resume-explorer.ps1` 而不需要指定完整路徑

### Feature Request-3 — P2

當執行 Capture 功能時, 目前只會保留最後一次的標籤頁組合, 並會覆蓋掉之前的組合. 建議至少提供 2-3 個組合的保留, 以便使用者可以回溯到之前的標籤頁組合, 而不會因為覆蓋而失去之前的組合.

### Feature Request-4 — P2

將此功能整合進其他專案 `restart-win-explorer-scripts` 和 `restart-windows-taskbar`, 以便在重啟 Windows Explorer 或 Windows Taskbar 時, 可以自動恢復之前的標籤頁組合, 提升使用者體驗. 但不是單純複製貼上 src code, 注意 DRY 原則和 SRP 原則, 需要將共用的功能抽象化成模組或函式庫, 以便在不同專案中重複使用, 並且方便維護和更新.

### Feature Request-5 — P3

是否有實作圖形化使用者介面（GUI）的需求？目前工具透過 PowerShell 參數執行 Capture、Preview 與 Restore；可評估是否需要 GUI 來檢視 Snapshot、選擇操作或呈現執行結果，再依使用情境決定是否實作。

## Tasks

### Task-1 — P1

為 `resume-explorer.ps1` 建立自動化測試，涵蓋 Snapshot 讀寫與驗證等可單元測試的邏輯；並評估在支援的 Windows 環境中加入端對端測試，驗證 Explorer 視窗與 Tabs 的還原行為。

### Task-2 — P2

若開起的路徑或檔案不存在，應記錄警告訊息，並跳過該路徑或檔案。不需要中斷整個還原流程。
