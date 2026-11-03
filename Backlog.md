# Backlog

## Priority convention

- **P0 — Critical:** 資料遺失、安全性重大缺陷或核心功能完全不可用，必須立即處理。目前沒有已確認的 P0。
- **P1 — High:** 已觀察到的核心可靠性問題、顯著效能／資源成本，或支撐後續修復的必要測試。
- **P2 — Medium:** 有價值但非阻斷性的功能缺口、使用體驗改善與整合需求。
- **P3 — Low:** 可選的便利性與擴充功能，待較高優先級項目完成再評估。

優先級表示**目前的建議處理順序**，不代表排程承諾；必要時依重現率、影響範圍及實測證據重新調整。`Done`／`Closed` 是狀態，不是優先級。

## Open Issues

### Issue-5 — P2 — Explorer 多 Process／異常累積是否與 Restore 有關（待確認）

- **原始問題**：執行 `restart-win-explorer-scripts/scripts/restart-file-explorer.bat` 時，`taskkill /f /im explorer.exe` 曾回報終止 **38 個** `explorer.exe` PID；另一次唯讀觀察顯示 **9 個** Process。兩次為不同時間的觀測，均缺乏操作前後基準、可見視窗／Tabs 對應及長期趨勢；**數量多不等於 Process／Memory Leak，也未證實由 `resume-explorer` 造成**。
- **範圍與拆分（2026-11-02）**：本 Issue **僅追蹤 Explorer Process 數量、生命週期、可能的重複建立／遺留及 `resume-explorer` Restore 的關聯**。檔案右鍵／雙擊引發的 `Not Responding`、Google Drive Shell extension／Named Pipe 等待及退出 Drive 後的恢復，另列為 **Issue-6（Completed／Mitigated；見下方 Completed）**；不要以該 Hang 的解除證明本 Issue 已修復，也不要將 Process 多寡直接當成該 Hang 的根因。
- **目前判斷／優先級**：尚未確認多 Process 是 Windows Explorer 正常的每視窗／隔離行為、其他工具所建立，還是 Restore 操作產生異常累積。因缺少可重現的資源成本或功能缺陷證據，**降為 P2**；若證實可重現的 Process 漏失、資源耗盡或核心操作受阻，再升為 P1。
- **調查路徑（唯讀優先）**：在同一台機器／Session，於 **未執行 Restore、首次 Restore、重複 Restore、關閉已還原視窗後**分別記錄 `explorer.exe` PID、Parent PID、StartTime、CommandLine、SessionId、MainWindowHandle、CPU／Working Set；比對 HWND／Shell COM 的視窗與 Tab identity，確認有無不對應可見視窗的殘留 Process。分開量測每次操作的 **新增、退出與最終淨增加數量**，不要比較不同環境的一次性總數。
- **程式碼檢查**：優先檢查 `OpenWindow`、每 Group 建立視窗的預期行為、Restore／Retry 再次執行、失敗或超時分支，以及 Issue-2 曾出現的 `-WindowStyle Hidden` 可見性 regression。驗證是否有重複建立或遺留，而非預先假定有 Bug。必要時在隔離測試環境重現並量測 Process／COM observation 成本，與 Issue-4 分開判斷因果。
- **RCA-first／互動式 Debug Gate**：Phase 0–2 先建立基準、收集唯讀證據及控制變因重現；**若仍無法定位根因，應先在可重設的隔離 Windows 測試環境進行互動式 Debug（例如追蹤 `OpenWindow` 呼叫次數、PID／HWND 變化、失敗分支與 Process creation/exit），找到具體可重現的錯誤機制後，才考慮修改現有程式碼**。不得因 Process 數量偏多就盲目加入清理、強制結束 Explorer、重構 COM 或改變 Restore 語意；若證據顯示為正常行為，直接以非缺陷結案。
- **詳細調查／有條件修復計畫**：[`plans/resume-explorer-Issue-5-process-lifecycle-rca-plan.md`](plans/resume-explorer-Issue-5-process-lifecycle-rca-plan.md)（**Proposed / RCA Required**；Phase 0–2 先建立基準、控制變因與必要的 Interactive Debug，取得可重現的本程式缺陷證據後才進行最小修復）。已歸檔的 [`plans/DONE/resume-explorer-Issue-6-drivefs-shell-hang-rca.md`](plans/DONE/resume-explorer-Issue-6-drivefs-shell-hang-rca.md) 是 **Issue-6 Closed (Mitigated)** 的歷史 RCA，不是 Issue-5 的修復計畫。
- **驗收／安全限制**：若多 Process 都能對應到預期視窗且生命週期正常，記錄基準並結案為非缺陷；若可證實異常累積，先提供最小重現與修復方案，再做隔離測試。**不可為診斷任意 `taskkill /f /im explorer.exe` 或清理未知 PID**。上述批次檔將 `#` 當 CMD 註解所產生的 `'#' is not recognized` 是**另一專案的獨立語法問題**，不納入本 Issue 的因果推論。

### Issue-4 — P1 — 同步 COM/UIA 呼叫超過 Restore deadline（待 RCA）

- **實際證據**：2026-11-01 的 18-item Restore 有 13 Verified、1 OutcomeUnknown（Group 6 / Tab 3，`NavigationTimeout`）、4 NotAttempted。該項目共耗時 28,545 ms；Navigation 僅有一筆觀測，時間標記 15,813 ms，`RawCount=68`、`UniqueCount=68`，該觀測包含目標路徑，但尚不足以確認指定候選 identity 持續穩定。
- **原因未定**：全域 Shell COM 列舉／單一物件變慢、Explorer 負載、焦點／Tab 互動或同步呼叫阻塞皆仍是假設。現有 deadline 只限制輪詢邊界，**無法中止正在執行的同步 COM/UIA 呼叫**。
- **修復方向**：先量測每次 Observe 的 wall-clock duration、階段、deadline overshoot、列舉數量與慢呼叫位置；再比較減少不必要觀測、target-aware 快速路徑及具安全隔離的 worker 設計。不應僅將 10 秒調高，或以直接殺執行緒的方式中止有副作用的 COM 呼叫。
- **驗收**：在高 Tab 數、慢 VDI、同步阻塞與視窗互動下維持 identity safety、checkpoint 及有限的可觀測 deadline 語意；不能新增重複 Invoke／Navigate。
- 詳細方案：[`plans/resume-explorer-Issue-4-synchronous-timeout-plan.md`](plans/resume-explorer-Issue-4-synchronous-timeout-plan.md)（Issue-4：同步操作超時 RCA 與修復方向）。

### Issue-1 — P2

這種路徑沒有打開 "H:\fake-path\dummy.zip"

### Issue-3 — P2 — Restore 不應依賴滑鼠焦點／前景視窗（RCA-first／待驗證）

- **已確認實作／證據邊界（2026-11-02 Review）**：目前 Restore 使用目標 Root HWND 的 UIA `AddButton`／`InvokePattern`、Shell COM `Navigate2`、Raw HWND 分組與候選 Tab identity／Fingerprint 驗證；**不使用 SendKeys 或滑鼠座標**。但**尚無受控證據**證實切換前景應用會造成失敗，也不能因使用 UIA/COM 就推論完全不受 active Tab 影響；不預先修改 Restore。
- **產品契約**：單純切至 Chrome／Visual Studio（A），或僅將另一 Explorer 視窗帶到前景（B），不應導覽錯誤 Tab 或替換既定目標 identity。目標 Explorer 內切 active Tab（C）需要實測；在目標手動新增／關閉／導覽 Tab（D）或關閉視窗（E）屬共享狀態變更，無法確保繼續，但必須 **fail closed**。新建同路徑無關 Explorer 視窗（F）不可被誤認成工具建立的 Window。
- **調查／根因判斷**：在隔離可重設 Windows 桌面以同一 Snapshot、環境、timeout 比較無互動對照與 A–F，分階段記錄原始／Root HWND、PID／Fingerprint、Identity 集、Path、可靠性、ReasonCode、Invoke／Navigate flags、時間及最終實際導覽結果。區分 UIA 可用性、active Tab 對 COM 觀測的影響、人為競爭與 Issue-4 的同步延遲；無法重現時記錄結果，不作猜測性修復。
- **修復門檻／回歸**：先建重現案例與 deterministic adapter regression，再依可證實的相依性做最小修復；嚴禁以 active Tab、path-only、Last View、盲目聚焦、SendKeys、放寬 identity 或重試副作用來掩蓋問題。保留 Issue-2 atomic checkpoint、單次 Invoke／Navigate、OutcomeUnknown 與 PreviewRetry／Retry 契約。驗收首要條件是**不得導覽到無關既有 Tab**；A/B 不因單純焦點變更錯選，C–F 不確定時保守停止。
- **邊界與依賴**：Feature Request-1 的「Restore 自身不顯示／不搶焦點」是獨立要求；Issue-4（P1）負責同步 COM/UIA Timeout；Task-3 單執行 CLI Lock 不會防止使用者改動 Explorer。可先做 Issue-3 焦點測試矩陣，不必等待完整 Task-1 測試框架；仍以 Issue-4／Task-1 既有 P1 優先級排序。
- **現況**：Proposed / Unverified，**沒有實作 Focus fix、沒有實機驗收或完成證據**。詳細方案：[`plans/resume-explorer-Issue-3-focus-independence-plan.md`](plans/resume-explorer-Issue-3-focus-independence-plan.md)。

## Feature Requests

### Feature Request-6 — P2 — Error-aware / Run-family-aware 同步 Report Cleanup（待調查／規劃）

- **2026-11-02 Review／唯讀實測**：原始 Report **3,002,321 bytes**（18 Items、**83** Diagnostics.Samples、**5,115** 累積 Views；原紀錄 87／5,119 已校正）。在**記憶體中**清空 Samples.Views 後重序列化為約 **116,701 bytes**；僅 minify 為約 **1,514,104 bytes**。這確認重複保存全域 Views 是主要容量來源，但**尚未證實是 Issue-4 Timeout 根因**；原始 Report 未被修改。
- **新決策／實際現況（2026-11-02）**：採 **Error-aware、Run-family-aware** 歷史保留政策，先量測真實磁碟、checkpoint serialize/write 與記憶體成本，不與 Issue-4 COM/UIA Timeout 混淆。現行 writer/reader **仍為 V1 Full**，沒有 Report retention/delete CLI；`5afd928` 雖以 `feat` 命名，實際只提交 Markdown，**沒有實作 FR-9 Compact／Full**。FR-9 的診斷等級屬獨立需求，本 FR 不要求立即修改 Schema。
- **三層 Retention（候選，尚未實作）**：**A** 未解決／未審核異常與狀態不明的 Family **全部保護**；**B** 曾有異常、經使用者**明確確認已處理**的完整 Families **保留最近 5 個**；**C** 全部正常 Verified 的完整 Families **保留最近 1 個 Baseline**（可考慮安全寬限期）。以 Root + 所有 Retry 子孫 + Sidecars 為單位，**絕不依單個 JSON 輪替**。5+1 是 soft target；Pin、活躍／Locked、OutcomeUnknown、Aborted、缺漏／損壞／自訂路徑等仍優先保護。
- **Single-instance Requirement（全命令互斥）**：**同一 Windows 使用者的新版本 `resume-explorer.ps1` 一次只能執行一個命令**，包含 `Capture`／`Preview`／`Restore`／`PreviewRetry`／`Retry`／未來 `Cleanup`。建議 CLI 最外層持有 `%LOCALAPPDATA%\ResumeExplorer\resume-explorer.instance.lock` 的 OS 排他 `FileStream`（`FileShare.None`），鎖檔位於 `Runs` 之外且永不清理；第二個命令**立即拒絕，不等待**。從 Action 開始前直到同步清理完成都持有鎖，由 `finally`／程序結束釋放。這是**未實作的新 CLI 行為**；舊版腳本、跨帳號／機器或外部寫入者不受保證。詳見下方 **Task-3** 與 FR-6 計畫。
- **Classification／Safety Gates**：`Completed` ≠ 全部 Verified；Root `OutcomeUnknown` 即使後代 Retry Verified，**也不可自動認定已處理**，需獨立的使用者 Review/Pin 狀態，且不得改寫 Report 使 PreviewRetry hash 失效。先交付**唯讀 Family inventory／分類與 DryRun**，再完成 single-instance 測試，最後才考慮顯式 opt-in Cleanup。**全命令鎖取代大型並行鎖管理器**，但跨檔刪除中斷、舊版／外部存取、完整 Family revalidation 仍需最小 fail-closed 防護；無法證明安全則**不實作刪除**。保留原 checkpoint、attempt flags、Run lineage、Retry hash/lock，不在日常 Explorer／VDI 壓測。
- **同步清理方式（無排程／背景工作）**：在同一 CLI **已持有 single-instance lock** 的情況下正常執行 Restore／Retry → 最後 checkpoint 成功 → 原 Summary 顯示 → 原有 Retry family lock 釋放 → 同步有界清理其他合資格舊 Families → 最後才釋放全命令鎖並返回。主操作 Aborted／checkpoint 失敗就略過 Cleanup、保留原例外；無候選／預算不足只 Deferred。其他 Action **仍取得全命令鎖，但不觸發 post-run 清理**。Cleanup 失敗不得改變 Restore／Retry 的 Status 或 exit code。**先 opt-in；未來若預設同步清理須另做相容性審核與 opt-out**，不使用 Scheduler、Timer、Background Job。
- **詳細階段／狀態**：**Reviewed / Proposed，尚未改程式碼、未刪除 Report**。Phase 0 唯讀量測；Phase 1 Family graph／異常分類；Phase 2 Review/Pin + DryRun；**Phase 2A 全 CLI 單一執行保護**；Phase 3 只有跨檔中斷等最小安全 Gate 通過才提供顯式手動 Cleanup；Phase 4 Restore／Retry 後同步整合。無 Scheduler／Background Worker／Lock Manager；若安全或回傳延遲無法接受則只保留 DryRun／手動能力。優先級 P2。詳見 [`plans/resume-explorer-Feature-Request-6-report-size-plan.md`](plans/resume-explorer-Feature-Request-6-report-size-plan.md)。

**實作優先序／明確依賴（2026-11-02）**：

1. **Task-4（S16 測試基線）已完成修復與跨版本驗收；下一個建議獨立實作項目：Task-3（Single-Instance CLI Guard）**。Task-3 不需要等待 FR-6 的 Report 容量量測、分類／DryRun，也**不依賴 Issue-6**；先以隔離、跨 Shell 雙 Process 測試驗證，完成後可單獨交付。
2. **FR-6 Phase 0 → Phase 1 → Phase 2**：唯讀容量基線 → Family graph／分類 → Review/Pin／DryRun。這條**不刪檔**的工作線可以在 Task-3 **之前或並行**進行，**不以 Task-3 為前置條件**。
3. **FR-6 Phase 3（Opt-in Safe Cleanup）**：**必要前置 = Task-3 驗收通過 + FR-6 Phase 0–2 的分類／DryRun 證據與驗收 + 跨檔中斷恢復安全 Gate**；不符合其中任一條件即不實作 Delete。
4. **FR-6 Phase 4（Post-Run Synchronous Cleanup）**：**必要前置 = FR-6 Phase 3 已通過驗收**，再整合 Restore／Retry 成功結束後同步執行，並維持 Single-Instance Lock 覆蓋整個命令。**FR-9 Compact／Full 不是以上任何階段的前置條件**。

此順序是**Task-3 與 FR-6 之間的相對實作次序**，不代表把兩者提升為全專案 P1；既有 Issue-4／Task-1 的 P1 仍照既有優先級判斷。**Issue-6** 指 Google DriveFS Explorer Hang 的已緩解歷史事件（Completed），與本處 **Feature Request-6** 是不同項目，互不依賴。詳細計畫見 [`plans/resume-explorer-Feature-Request-6-report-size-plan.md`](plans/resume-explorer-Feature-Request-6-report-size-plan.md)。

### Feature Request-9 — P2 — JSON Report 診斷等級：Compact Default／Full Opt-in（待設計）

- **功能需求**：**保留 JSON Report 作為 Restore／Retry 的核心功能**；本需求實作後，日常預設 `Compact`，需要深入 RCA 時可明確選擇 `Full`，不以關閉安全 Report 交換容量或效能。
- **兩種等級**：Compact 保留全部安全／Retry 資料、Phase／可靠性／錯誤與關鍵歧義摘要，不再在每個 Sample 重複持久化全部 Explorer Views；Full 盡可能保留現行詳細 Views／Errors，注意敏感路徑及有界容量／截斷訊號。單一 Run 維持一份 JSON 與一套 Reader／Retry 契約。
- **向後相容**：未來可考慮 `-DiagnosticLevel Compact|Full`，不要借用 PowerShell `-Verbose` Common Parameter；若 JSON 結構變更，必須明確 versioning、更新文件／版本號／測試、兼容歷史 V1 與新舊混合 Retry 家族，且不得改變副作用前原子 checkpoint 或 OutcomeUnknown 安全判斷。
- **與 FR-6 分工**：這是**長期功能期望而非已實作行為**。目前仍是 V1 Full；**FR-6 先量測是否存在實質效能／儲存問題，FR-9 的實作優先序再依證據調整**，不可反過來要求 FR-6 先導入 Compact／Schema V2。
- **狀態／計畫**：**Feature Requirement / Proposed，尚未實作**。見 [`plans/resume-explorer-Feature-Request-9-diagnostic-level-plan.md`](plans/resume-explorer-Feature-Request-9-diagnostic-level-plan.md)。

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

## PowerShell Runtime Support Policy（2026-11-02）

- **正式支援 Windows 上的 PowerShell 7（`pwsh.exe`）主版本；不再要求 Windows PowerShell 5.1（`powershell.exe`）相容性。** 此為後續開發／測試政策，不回溯否認 Task-4 已完成的 5.1 測試證據。現有兩套離線測試在 PS7.6.1 為 Issue2 39/39、RestoreSummary 17/17（Exit 0）。
- 各新功能（含 Task-3、FR-6）在不同 `pwsh.exe` processes、Terminal hosts 與工作目錄下仍需正確運作；**跨 Shell／跨 Process 不等於跨 PowerShell 主版本**。不得為維持 5.1 相容性限制適當的 PS7 技術選型。
- 真實 Windows 11 Explorer／Shell COM／UI Automation E2E 在 PS7 尚未因此通過；上線前必須獨立驗證。**追蹤：Task-5 PowerShell 7 Explorer E2E Smoke Test**（詳見下方）。保留 CLI Actions／參數、Snapshot／Report JSON、Retry 身分與 checkpoint 安全契約；如有必要的破壞性變更須明確記錄。

## Tasks

### Task-1 — P1

為 `resume-explorer.ps1` 建立自動化測試，涵蓋 Snapshot 讀寫與驗證等可單元測試的邏輯；並評估在支援的 Windows 環境中加入端對端測試，驗證 Explorer 視窗與 Tabs 的還原行為。**目前已有** `tests/Issue2.Tests.ps1`（39 tests）及 `tests/RestoreSummary.Tests.ps1`（17 tests）；較完整的 Pester/CI 測試基建仍為計畫。真實 PS7 Explorer 最小 E2E 驗收獨立列為 **Task-5**，避免被 Task-1 的完整框架建置阻塞。

### Task-5 — P1 — PowerShell 7 Explorer E2E Smoke Test（Proposed／尚未實作）

- **目標／原因**：2026-11-02 已決定正式支援 Windows 上的 **PowerShell 7-only**。既有 PS7.6.1 離線回歸（Issue2 **39/39**、RestoreSummary **17/17**，Exit 0）與 STA 模式載入 UIAutomation assemblies 已驗證，但**尚未執行真實 Shell COM / UIA / Explorer Tabs E2E**；不能把離線成功當成 PS7 GUI 相容性通過。
- **E01 Capture / Restore**：在**獨立、可重設、互動式** Windows 11 測試使用者 Session 建立 2 個 fixture Explorer Windows、3 個 Tabs（A|B、C）；正式 CLI 以明確 Snapshot/ReportPath Capture → Preview → Restore，必須驗證新建立的 **2 個可見視窗、3 個 Tabs、原分組不變、原視窗未被修改、Report 3/3 Verified**，另以獨立 observer/人工核對 GUI。
- **E02 PreviewRetry / Retry**：用**不同 RunId 的合法測試 Snapshot**（A 存在、B 暫不存在）使初次 Restore 得到 A Verified / B SkippedInvalidPath；建立 B 後執行 PreviewRetry，從 sidecar 驗證目標 fingerprint，再以明確 HWND／Group/Item 補做 B。驗證 child Report **1/1 Verified**、parent Report hash 不變、只在 A 測試 Window 新增 B Tab；禁止改寫報告、Path-only 猜選或使用 `-IncludeUncertain` 偷跑不明項目。
- **安全 Gate**：必須明確 opt-in GUI 操作、先驗證專用互動桌面與所有 Explorer HWND 都是 fixture；Capture 會列舉**全部** Explorer Windows，故工作中的 Explorer Session、Remote 背景 Session 或有不明窗口時 **Blocked／NotRun**。禁止 kill/restart Explorer、SendKeys、繞過 Execution Policy、自動重跑有副作用的 Restore/Retry；失敗保留證據並人工清理測試 Window。
- **實作次序／依賴**：先離線基線 → 獨立安全 Preflight/Runner → 真實 E01 → 真實 E02 → README/測試結果。**不依賴** Pester 5、全面 Module 重構或 Task-3 Single-Instance Lock；若 Task-3 先實作，本 Smoke 須遵守全域 Lock 且序列執行。本項是 PS7-only 真實 Explorer 發布驗收關卡，**不是** Task-1 全部 Unit/CI 建置的替代品，亦不宣稱修復 Issue-3/4。
- **詳細計畫／驗收矩陣**：[`plans/resume-explorer-Task-5-powershell7-explorer-e2e-smoke-plan.md`](plans/resume-explorer-Task-5-powershell7-explorer-e2e-smoke-plan.md)。**狀態：僅規劃完成，E01/E02 尚未執行；不能標記 Completed。**

### Task-4 — P1 — RestoreSummary S16 JSON 格式敏感斷言（Completed／2026-11-02）

- **已重現／確認（2026-11-02）**：`tests/RestoreSummary.Tests.ps1` 在 Windows PowerShell **5.1** 執行時，S01–S15 通過但 **S16 Assertion Failed**；PowerShell **7** 則 **17/17 通過（Exit Code 0）**。受控診斷確認原始 `IOException` 物件保持一致、`Checkpoint failed` Warning 恰好 1 筆、Console fallback JSON 可解析且 `SchemaVersion=1`；S17 的原始 Exception 保護亦經獨立診斷驗證。
- **已確認根因**：S16 使用 `$text.Contains('"SchemaVersion": 1')` 鎖定單一空格，但 PowerShell 5.1 的 `ConvertTo-Json` 實際輸出 `"SchemaVersion":  1`（兩個空格）。這是**測試把合法 JSON 排版空白當成契約**，不是已證實的 Production Checkpoint／Schema 缺陷；不得為配合斷言去修改 Production JSON。
- **已實作（Test-only）**：僅替換 S16 的格式敏感 JSON substring assertion，從 InformationRecord 的 MessageData 文字取得唯一 fallback，以 `ConvertFrom-Json` 驗證 SchemaVersion、RunId、State、Items 數量及首項 Group／Item／Status／RequestedPath。保留原 Exception identity、唯一 checkpoint warning、Report 路徑、禁止假成功文字等 assertions；同一 S16 內新增 12 組缺失／重複／非法／錯誤欄位負向 fixture，均須被拒絕。沒有修改 Production、Schema 或其他測試行為。
- **優先序與驗收**：先以獨立 Test-only 變更處理本 Task，再進行 Task-3（Single-Instance CLI Guard）的實作基線驗證；需 `RestoreSummary.Tests.ps1` 在 PS5.1 與 PS7 **17/17 Passed、Exit Code 0**，既有 `Issue2.Tests.ps1` 回歸通過，且**不操作真實 Explorer**。本項 P1 是測試可靠性／後續開發基線，非已證實 P1 Production 缺陷。
- **驗收結果**：PowerShell **5.1.22621.6931** 與 **7.6.1** 各自完整執行 Summary **17/17**、Issue2 **39/39**，四次 Exit Code 均 **0**。沙箱內 PS5.1 看不到使用者 RemoteSigned 政策；沙箱外依現有 CurrentUser RemoteSigned 完成實跑，沒有更改／繞過政策，沒有真實 Explorer 操作。Task-3 的 S16 baseline gate 已解除，Task-3 功能仍未實作。
- **詳細 RCA 與結案證據**：[`plans/DONE/resume-explorer-Task-4-restore-summary-s16-regression-plan.md`](plans/DONE/resume-explorer-Task-4-restore-summary-s16-regression-plan.md)（**Completed；Test-only，已歸檔至 DONE，未自動 commit**）。

### Task-3 — P2 — Single-Instance CLI Guard（Task-4 測試基線處置後建議獨立實作；FR-6 Phase 3/4 前置條件）

- **需求（跨 Shell）**：同一 Windows 使用者、**共用相同鎖檔實際路徑**的新版 `resume-explorer.ps1`，不論透過不同 PowerShell 7 processes、CMD→`pwsh.exe`、Windows Terminal、VS Code Terminal 或不同工作目錄啟動，所有 Action（`Capture`／`Preview`／`Restore`／`PreviewRetry`／`Retry`，未來含 `Cleanup`）**同一時間只允許一個執行**。第二個命令在執行任何 Explorer／Snapshot／Report 副作用前 fail fast，**不等待、不排隊、不背景重試**。跨帳號／機器、舊版 CLI 或未共用鎖路徑不保證互斥。
- **建議最小實作**：從 Windows 使用者的 LocalApplicationData 取得**固定絕對路徑**（候選 `%LOCALAPPDATA%\ResumeExplorer\resume-explorer.instance.lock`），不依賴 `$PWD`、Script 目錄、`-ReportPath`；在 CLI 最外層透過 OS 排他檔案開啟（`.NET FileStream`、`FileShare.None`）取得鎖。從 Action 開始到 **final checkpoint → summary → Retry family lock 釋放 → 同步 Cleanup 完成／跳過** 都保持 handle 開啟，最後在 `finally` 關閉；程序被終止時 OS 釋放 handle。檔案位於 `Runs` 之外，**不刪除 lock anchor，也不以 `.lock` 檔是否存在判定 Busy**；sharing violation 與 ACL／磁碟錯誤分開報告並 fail-closed。
- **安全與相容性**：保留原有 per-family `Retry` lock、原子 checkpoint、Report JSON 與既有 CLI 參數／正常輸出。只保證遵守同一鎖的新版 CLI；舊版腳本、不同使用者與外部工具仍不受約束。此變更使既有同時執行的命令改為拒絕，應更新 README／版本與測試。拒絕 lock 失敗不得誤啟動 Explorer。
- **測試／交付**：在**隔離鎖檔路徑**下，以兩個獨立 PowerShell Processes 測試兩個獨立 PowerShell 7 processes、不同 Terminal Tabs／VS Code／CMD→`pwsh.exe` 啟動、不同 `$PWD`、所有 Actions 與 cleanup 期間第二命令 fail-fast；驗證 sharing violation、權限錯誤、例外／Ctrl+C／程序終止與檔案仍存在但 handle 已釋放時能重新取得鎖。跨 RDP Sessions 只在確定使用相同本機鎖路徑時納入實測；不擾動真實 Explorer 或現有 Report。詳細 Review／實作計畫：[`plans/resume-explorer-Task-3-single-instance-cli-guard-plan.md`](plans/resume-explorer-Task-3-single-instance-cli-guard-plan.md)（2026-11-02 Reviewed / Proposed，**尚未實作**）；與 FR-6 的依賴：[`plans/resume-explorer-Feature-Request-6-report-size-plan.md`](plans/resume-explorer-Feature-Request-6-report-size-plan.md) §5.2、Phase 2A。

### Task-2 — P2

若開起的路徑或檔案不存在，應記錄警告訊息，並跳過該路徑或檔案。不需要中斷整個還原流程。

---

## Completed

### Issue-6 — Closed (Mitigated) — Explorer `Not Responding`／Google Drive Shell 整合疑似相關

- **Closed (operational recovery):** 2026-11-02。自 Issue-5 拆分；此處的 **Closed 僅表示當次 Explorer 無回應已解除、一般操作已恢復**，**不是根因已證實、程式修復完成或永久不再復發**。
- **與本程式的因果關係／責任歸屬（截至 2026-11-02）**：**目前沒有證據顯示 `resume-explorer` 的 Capture、Restore 或 Restart 造成這次 Explorer `Not Responding`；此事件不得列為已確認的本程式 Bug。** 已取得的直接診斷線索是 `drivefsext.dll` 的 Named Pipe wait，且 Quit Google Drive 後 Explorer 恢復，故**優先懷疑 Google Drive／Windows Shell 整合**。但尚無受控的 Drive 重啟對照或 `resume-explorer` 操作前後對照，**不能宣稱已證明 Google Drive 為唯一根因，或完全排除本程式可能有間接影響**。在取得與本程式相關的可重現證據前，無須修改 Restore 程式碼；Issue-5 的多 Process 問題仍獨立調查。
- **環境與症狀**：發生於個人 **Dell G15 Windows PC**，非 VMware Horizon VDI。對檔案**按右鍵（未選選單指令）**或雙擊 PDF／MP4 時，所操作的 Explorer 視窗／Process 會 `Not Responding`；其他 Explorer Process 仍可正常操作；由已開啟的閱讀器／播放器使用 `File > Open` 則正常。
- **診斷證據**：曾卡住的 Explorer PID `44244` 之 Wait Chain 關聯 TID `89092`、`51124`，其 Stack 含 `drivefsext.dll → KERNELBASE!WaitNamedPipeW → ntdll!ZwFsControlFile`。支持 Google Drive Shell 整合／IPC 等待的關聯性，**未證實 pipe/server、精確故障機制或 Google Drive 本身的 Bug**。上述 PID／TID 僅為歷史觀測值。
- **已觀察到的恢復**：使用者從系統匣 **Quit Google Drive** 後，先前無回應的 Explorer 恢復；新開 `This PC` Tab 曾持續「正在處理...」約 **3–5 分鐘**，完成後開檔與導覽恢復正常、反應速度可接受。沒有記錄退出 Drive 後再次獨立測試右鍵的結果，亦不能確認 Tab 緩慢與右鍵 Hang 是同一根因。
- **未完成的 RCA／再開條件**：尚未記錄 Google Drive 重啟後的 A/B 對照或長期穩定性，也**沒有證據顯示 `resume-explorer` 造成此 Hang**。目前不把 RCA 當成本專案阻斷項目；**若右鍵／開檔無回應復發，重新開啟 Issue-6（當次影響嚴重時評估 P1）**，依既有計畫先做安全的 Drive off/on 對照，再採集新 PID／Stack／Wait Chain，避免反覆誘發卡死。
- **歷史調查／後續手冊**：[`plans/DONE/resume-explorer-Issue-6-drivefs-shell-hang-rca.md`](plans/DONE/resume-explorer-Issue-6-drivefs-shell-hang-rca.md) 與 [`.agents/skills/explorer-shell-hang-investigator/SKILL.md`](.agents/skills/explorer-shell-hang-investigator/SKILL.md)；RCA 已按 Issue-6 更名並歸檔於 `plans/DONE/`，Skill 的 handoff 已更名為 `issue-6-handoff.md`；保留歷史證據與復發時的重新開啟條件。與現存 **Issue-5（Process 數量／生命週期）**分開追蹤。

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
