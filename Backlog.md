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

### Issue-3 — P2 — Restore 不應依賴滑鼠焦點／前景視窗（待驗證）

- **預期行為**：Restore 期間使用者點擊 Chrome、Visual Studio 等其他應用程式，或將 Explorer 切至背景，不應因此導覽錯誤 Tab、失去已確認的 Tab identity 或錯誤中止。這是**互動容錯性**，與 Feature Request-1 的「不顯示、不搶焦點」是兩個不同需求。
- **風險界線**：使用者對**正在還原的目標 Explorer** 手動新增、關閉、切換 Tabs 或關閉視窗，可能改變 UIA／COM 可觀測狀態；工具仍應保守停止，而不是猜選 Tab。是否連單純切換同視窗的 active Tab 都安全，需實機測試驗證，不預先宣稱。
- **調查及驗收**：加入前景應用切換、其他 Explorer 視窗切換、目標 Explorer 手動操作等分離測試；比較每次觀測的 HWND、PID、Identity、Path 與耗時，釐清焦點切換是否造成異常。不可只因時間上相近就歸因於滑鼠點擊。
- 詳細方案：[`plans/resume-explorer-Issue-3-focus-independence-plan.md`](plans/resume-explorer-Issue-3-focus-independence-plan.md)。

## Feature Requests

### Feature Request-6 — P1 — 精簡 JSON Report 與可控診斷資訊（待實作）

- **2026-11-02 Review／唯讀實測**：原始 Report **3,002,321 bytes**（18 Items、**83** Diagnostics.Samples、**5,115** 累積 Views；原紀錄 87／5,119 已校正）。在**記憶體中**清空 Samples.Views 後重序列化為約 **116,701 bytes**；僅 minify 為約 **1,514,104 bytes**。這確認重複保存全域 Views 是主要容量來源，但**尚未證實是 Issue-4 Timeout 根因**；原始 Report 未被修改。
- **決策**：預設 **Compact Diagnostics**，按 phase 累積計數／可靠性／錯誤摘要及有界關鍵樣本；詳細全域 Views 僅以 **Full opt-in** 且有限額提供。保持即時完整 Shell Observation 供 Restore identity／歧義判斷，僅精簡持久化投影；不把 minify／壓縮視為主要修復。
- **版本與安全**：建議**新 Report SchemaVersion=2**，Reader 同時接受 V1/V2，舊檔不遷移；保留 ReportPath、Run family、原始 Group/Item、Path、Status、ReasonCode、attempt flags、Fingerprint、OutcomeUnknown、PreviewRetry／Retry 判斷以及**副作用前原子 checkpoint**。診斷截斷只能丟棄非核心樣本，必須保留 dropped/truncated counters；不得截斷安全欄位或 JSON。
- **量化目標／測試**：同規模 Compact 初始軟性目標 **≤300,000 bytes**，先用合成 18 Items／83 Samples／5,115 Views benchmark 與 offline mock／V1-V2 Retry family tests 驗證；量測 checkpoint 時間、累計寫入 bytes 與記憶體；Full 另設樣本與診斷 byte budget。不可在日常 Explorer／VDI 自動 E2E 壓測。
- **狀態／詳細計畫**：**Reviewed / Proposed，尚未改程式碼**。見 [`plans/resume-explorer-Feature-Request-6-report-size-plan.md`](plans/resume-explorer-Feature-Request-6-report-size-plan.md)。

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
