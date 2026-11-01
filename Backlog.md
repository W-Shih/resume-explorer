# Backlog

## Priority convention

- **P0 — Critical:** 資料遺失、安全性重大缺陷或核心功能完全不可用，必須立即處理。目前沒有已確認的 P0。
- **P1 — High:** 已觀察到的核心可靠性問題、顯著效能／資源成本，或支撐後續修復的必要測試。
- **P2 — Medium:** 有價值但非阻斷性的功能缺口、使用體驗改善與整合需求。
- **P3 — Low:** 可選的便利性與擴充功能，待較高優先級項目完成再評估。

優先級表示**目前的建議處理順序**，不代表排程承諾；必要時依重現率、影響範圍及實測證據重新調整。`Done`／`Closed` 是狀態，不是優先級。

## Open Issues

### Issue-5 — P1 — 調查大量 Explorer Process 與重啟後持續卡頓／Not Responding（待 RCA）

- **發現**：執行 `restart-win-explorer-scripts/scripts/restart-file-explorer.bat` 時，`taskkill /f /im explorer.exe` 回報成功終止 **38 個** `explorer.exe` PID（本次輸出）；異常數量是否由 `resume-explorer` 產生尚未證實。批次檔使用 `#` 作註解，CMD 將其當成命令而顯示 `'#' is not recognized`；這是該批次檔獨立的語法問題，不能當作 Explorer Process 增多的原因。
- **新增症狀（2026-11-01）**：使用者回報即使已終止並重啟 Explorer，操作仍非常緩慢，甚至顯示 `Not Responding`。本次唯讀 `Get-Process explorer` 顯示 **9 個 Process**；其中 PID **10960** 的 `Responding=False`、`WorkingSet64=213049344` bytes（約 203 MiB）。單次 `Responding=False` 是需要進一步驗證的線索，並非診斷結果，亦不能據此認定 `resume-explorer` 或記憶體洩漏為根因。
- **待查問題**：區分正常的 Windows Explorer 多 Process／多視窗架構，與 `resume-explorer` 的每 Group 建立新視窗、Restore／Retry 重複執行、未顯示視窗或遺留 Process 的可能影響；也要排除其他工具或系統行為。不可只依 `taskkill` 數量判定 Memory Leak 或 Process Leak。
- **安全、唯讀調查**：在下次 Restore **之前與之後**記錄 `explorer.exe` PID、Parent PID、StartTime、CommandLine、SessionId、MainWindowHandle、視窗是否可見／可列舉，以及 Shell COM 的 HWND／Tab 對應；比較新建視窗與 Process 數量的增量，釐清是否存在無對應可見視窗的 Process。先檢查 `resume-explorer` 的 `OpenWindow` 及 Issue-2 的 `-WindowStyle Hidden` regression 是否與此相關。
- **重啟後 RCA**：先在未執行新 Capture／Restore 的情況下觀測 Explorer 是否持續卡頓，以區分 `resume-explorer` 呼叫期間的瞬時負載與重啟後獨立存在的系統問題。記錄 PID／啟動時間、個別視窗是否無回應、CPU／記憶體／I/O 隨時間的變化及 Windows Reliability Monitor／Event Viewer 的 Application Hang 或 Explorer crash 事件；必要時再評估 Shell extensions、Quick Access／Home、網路／OneDrive 路徑、索引或防毒掃描等外部因素。讀取事件紀錄時避免收集無關個人資料。
- **影響分析**：量測 Process 數量、Explorer／COM observation 耗時、記憶體占用與 Issue-4 `NavigationTimeout` 的相關性，但不將相關視為因果；必要時於隔離環境做控制變因 E2E。
- **安全限制／驗收**：不為診斷執行 `taskkill /f /im explorer.exe`、不自動關閉使用者視窗、不清理未知 PID；先確認是否異常，再提出最小修復並保留 Restore／Retry 的身份安全規則。`restart-file-explorer.bat` 的 `#` 註解問題應在該專案另行修正，不在本 Issue 擅自修改。

### Issue-4 — P1 — 同步 COM/UIA 呼叫超過 Restore deadline（待 RCA）

- **實際證據**：2026-11-01 的 18-item Restore 有 13 Verified、1 OutcomeUnknown（Group 6 / Tab 3，`NavigationTimeout`）、4 NotAttempted。該項目共耗時 28,545 ms；Navigation 僅有一筆觀測，時間標記 15,813 ms，`RawCount=68`、`UniqueCount=68`，該觀測包含目標路徑，但尚不足以確認指定候選 identity 持續穩定。
- **原因未定**：全域 Shell COM 列舉／單一物件變慢、Explorer 負載、焦點／Tab 互動或同步呼叫阻塞皆仍是假設。現有 deadline 只限制輪詢邊界，**無法中止正在執行的同步 COM/UIA 呼叫**。
- **修復方向**：先量測每次 Observe 的 wall-clock duration、階段、deadline overshoot、列舉數量與慢呼叫位置；再比較減少不必要觀測、target-aware 快速路徑及具安全隔離的 worker 設計。不應僅將 10 秒調高，或以直接殺執行緒的方式中止有副作用的 COM 呼叫。
- **驗收**：在高 Tab 數、慢 VDI、同步阻塞與視窗互動下維持 identity safety、checkpoint 及有限的可觀測 deadline 語意；不能新增重複 Invoke／Navigate。
- 詳細方案：[`plans/resume-explorer-Issue-4-synchronous-timeout-plan.md`](plans/resume-explorer-Issue-4-synchronous-timeout-plan.md)（Issue-4：同步操作超時 RCA 與修復方向）。

### Issue-1 — P2

這種路徑沒有打開 "H:\fake-path\dummy.zip"

### Issue-3 — P2 — Restore 不應依賴滑鼠焦點／前景視窗（待驗證）

- **預期行為**：Restore 期間使用者點擊 Chrome、Visual Studio 等其他應用程式，或將 Explorer 切至背景，不應因此導覽錯誤 Tab、失去已確認的 Tab identity 或錯誤中止。這是**互動容錯性**，與 Feature Request-1 的「不顯示、不搶焦點」是兩個不同需求。
- **風險界線**：使用者對**正在還原的目標 Explorer** 手動新增、關閉、切換 Tabs 或關閉視窗，可能改變 UIA／COM 可觀測狀態；工具仍應保守停止，而不是猜選 Tab。是否連單純切換同視窗的 active Tab 都安全，需實機測試驗證，不預先宣稱。
- **調查及驗收**：加入前景應用切換、其他 Explorer 視窗切換、目標 Explorer 手動操作等分離測試；比較每次觀測的 HWND、PID、Identity、Path 與耗時，釐清焦點切換是否造成異常。不可只因時間上相近就歸因於滑鼠點擊。
- 詳細方案：[`plans/resume-explorer-Issue-3-focus-independence-plan.md`](plans/resume-explorer-Issue-3-focus-independence-plan.md)。

## Feature Requests

### Feature Request-6 — P1 — 精簡 JSON Report 與可控診斷資訊（待實作）

- **實際證據**：同一份 2026-11-01 Report 的大小為 **3,002,321 bytes**（約 3.00 MB／2.86 MiB），僅 18 Items、87 個 Diagnostics.Samples，卻包含 **5,119 筆儲存的 View 記錄**，高度重複保存全域 Shell 觀測。
- **期望**：預設 Report 應保有 Run／Item 結果、ReasonCode、必要的事件時間與 Retry 安全依據，但不應每次 polling 都持久化全域全部 Explorer Views／Fingerprint。詳細 trace 應可透過明確指定的診斷模式取得，並設容量與樣本上限。
- **方案**：調查容量構成，優先改為每次觀測的精簡統計、階段摘要與異常時的有限樣本；必要時允許 opt-in 詳細 trace、大小上限與截斷計數，保持事故可診斷性。壓縮／minify 可作輔助，但不可取代去除冗餘資料。
- **相容性**：保留現有 ReportPath、原始 Group/Item、Status、ReasonCode、Run family 關係及 Retry 判斷；若改 Schema 須有明確版本策略與舊報告讀取測試。不能為縮小 Report 犧牲 crash checkpoint 或不明結果的安全保護。
- 詳細方案：[`plans/resume-explorer-Feature-Request-6-report-size-plan.md`](plans/resume-explorer-Feature-Request-6-report-size-plan.md)。

### Feature Request-1 — P2

當執行 `& .\resume-explorer.ps1 -Action Restore` 時，希望在背景還原 Explorer 視窗與標籤頁，不顯示或彈出 Explorer 視窗、不將其帶到前景，也不搶走目前使用中應用程式的焦點，以免打斷使用者操作。

此需求針對 Explorer 視窗本身的顯示與焦點行為，不是僅隱藏 PowerShell／Console 視窗。

先記錄期望行為，不預設實作方式，也不因技術難度預先縮減需求。可行性與開發成本留待後續評估；若無法可靠達成或成本不合理，可記錄原因並將此需求標記為 Rejected。

### Feature Request-3 — P2

當執行 Capture 功能時, 目前只會保留最後一次的標籤頁組合, 並會覆蓋掉之前的組合. 建議至少提供 2-3 個組合的保留, 以便使用者可以回溯到之前的標籤頁組合, 而不會因為覆蓋而失去之前的組合.

### Feature Request-4 — P2

將此功能整合進其他專案 `restart-win-explorer-scripts` 和 `restart-windows-taskbar`, 以便在重啟 Windows Explorer 或 Windows Taskbar 時, 可以自動恢復之前的標籤頁組合, 提升使用者體驗. 但不是單純複製貼上 src code, 注意 DRY 原則和 SRP 原則, 需要將共用的功能抽象化成模組或函式庫, 以便在不同專案中重複使用, 並且方便維護和更新.

### Feature Request-7 — P2 — 安全的 Explorer Restart + Restore 工作流程（待設計）

- **目的**：在需要重啟 File Explorer 時，提供可選的 `Capture → Restart Explorer → Restore` 一體化流程，降低手動操作成本；這是新增功能，不代表現有 Restore 有缺陷。可與 Feature Request-4 的跨專案整合共用模組，但不得以複製腳本取代 DRY／SRP。
- **能力邊界**：Snapshot 只保存已能 Capture 的 Explorer 視窗／Tab 路徑，**不能保證還原所有 Explorer／Shell 狀態**，例如進行中的檔案複製、未儲存操作、選取狀態、特殊 Shell namespace 或外部程式的 Explorer 相依工作；Restore 也可能 Partial／OutcomeUnknown。
- **安全前置條件**：先完成且驗證新 Snapshot 寫入成功、Schema／路徑有效、備份可讀並保留舊 Snapshot；預先提示強制終止 `explorer.exe` 的影響，提供 DryRun／Preview 與明確 opt-in 確認。若 Capture 失敗、Snapshot 不可靠或環境無法確認，**不得自動終止 Explorer**。
- **Restart 設計**：優先研究 Windows 支援的較溫和 Explorer 重啟方式與合適的範圍；不得預設 `taskkill /f /im explorer.exe` 是安全無損操作。確認 Explorer／Shell 恢復可觀測後才 Restore，並保留中斷與失敗後的人工復原指引。
- **Restore 安全性**：沿用 Issue-2 的 identity、單次 Invoke／Navigate、checkpoint、Partial／Retry 保護；不宣稱 Snapshot 存在就保證 100% Restore，也不因 Restart 自動對不明結果重試。
- **驗收**：先以隔離測試環境測試 Capture 失敗、Snapshot 過期／損壞、Explorer 啟動緩慢、部分 Restore、既有 Explorer 進程與多視窗情境；紀錄新舊 PID／視窗及結果。與 Issue-5 的 Process 數量 RCA 分開，不能把殺掉所有 Process 當成修復 Process leak 的證據。

### Feature Request-8 — P2 — 定時自動 Capture 與有限歷史快照（待設計）

- **目的**：在使用者沒有手動 Capture 的情況下，定期備份 Explorer 視窗／Tabs 路徑，讓意外 Explorer 結束或重啟後仍有可選的歷史 Snapshot 可用；僅恢復可觀測的路徑組合，不保證所有 Shell 工作階段狀態。
- **可調參數（初始候選，非硬性規格）**：預設評估每 **5 分鐘**自動 Capture，保留最近 **5 份有效快照**；允許調整為例如 3–10 份及其他間隔。先測量 CPU／COM 負載與 Snapshot 實際變更頻率，再決定合理預設值。
- **保留策略**：使用時間戳、唯一 ID 與來源標記，建立循環歷史；先原子寫入並驗證新 Snapshot，再清理超出上限的**自動**舊快照。Capture 失敗、部分列舉或空白／異常狀態不得覆蓋最近的有效版本，且不可刪除手動建立或標記保留的快照；必要時保留上一份有效內容及失敗診斷。
- **避免無效工作**：優先評估內容雜湊／結構差異，Explorer 視窗與 Tabs 未變動時不必每次產生相同歷史版本；限制同時僅有一個 Capture、設單次執行超時與錯誤退避，避免背景排程重疊或持續占用 COM 資源（參照 Issue-4）。
- **背景執行與生命週期**：比較 Windows Task Scheduler（登入使用者的互動工作階段）與常駐程序等方案，確認登出、休眠／喚醒、遠端桌面、使用者權限與無 Explorer 的情況；提供明確啟用／停用、狀態檢視及解除安裝設定，不預設建立排程。
- **還原體驗**：Preview 列出快照的時間、來源（manual／auto）、有效性與視窗／Tab 數量；使用者明確選擇歷史版本 Restore，不自動在開機時覆蓋既有 Explorer 視窗。與 Feature Request-3 共用 Snapshot 歷史／保留機制；Feature Request-7 可選擇已驗證的最新版本作為 Restart 前的候選備份。
- **驗收**：涵蓋無變更、頻繁變更、路徑無法讀取、空狀態、連續失敗、競態寫入、寫檔中斷、歷史輪替、手動快照保護、登入／登出和大量 Explorer Tabs；確保不會因定時 Capture 引入 Restore 失敗或刪除最後一份有效備份。

### Feature Request-2 — P3

詢問是否將執行檔加入系統 PATH, 以便在任何目錄下都可以直接執行 `resume-explorer.ps1` 而不需要指定完整路徑

### Feature Request-5 — P3

是否有實作圖形化使用者介面（GUI）的需求？目前工具透過 PowerShell 參數執行 Capture、Preview 與 Restore；可評估是否需要 GUI 來檢視 Snapshot、選擇操作或呈現執行結果，再依使用情境決定是否實作。

## Tasks

### Task-1 — P1

為 `resume-explorer.ps1` 建立自動化測試，涵蓋 Snapshot 讀寫與驗證等可單元測試的邏輯；並評估在支援的 Windows 環境中加入端對端測試，驗證 Explorer 視窗與 Tabs 的還原行為。

### Task-2 — P2

若開起的路徑或檔案不存在，應記錄警告訊息，並跳過該路徑或檔案。不需要中斷整個還原流程。

---

## Completed

### Issue-2 — Closed (implementation complete)

- **Completed:** 2026-11-01

- **Result:** 已實作穩定 baseline、單次 Invoke、候選 Tab identity／路徑驗證、保守停止、checkpoint，以及 PreviewRetry／Retry；後續可見性 regression 已修正。

- **Implementation commits:** `7b6866b`, `b3f4197`, `990ec5f`

- **Plan:** [`plans/DONE/resume-explorer-Issue-2-fix-plan.md`](plans/DONE/resume-explorer-Issue-2-fix-plan.md)

- **Validation:** [`ISSUE2-VALIDATION.md`](ISSUE2-VALIDATION.md)。核心修復已結案，但原 Horizon VDI 完整實機驗收與 production RCA 尚未完成；不可視為 beta.2 發布驗收通過。後續問題另由 Issue-3、Issue-4、Feature Request-6 追蹤。



### Restore Result Summary & Unverified Item Diagnostics — Done

- **Completed:** 2026-11-01

- **Result:** Restore／Retry 的 Complete／Partial／Interrupted／Empty 摘要、未驗證 Group／Tab／Path／原因、Warning 與 PreviewRetry 指令已實作。

- **Implementation commit:** `319da25`

- **Plan:** [`plans/DONE/resume-explorer-restore-summary-implementation-plan.md`](plans/DONE/resume-explorer-restore-summary-implementation-plan.md)

- **Validation:** [`ISSUE2-VALIDATION.md`](ISSUE2-VALIDATION.md)，原 39 項與新增 17 項離線測試通過；不代表 Explorer 可見性已完整驗收。
