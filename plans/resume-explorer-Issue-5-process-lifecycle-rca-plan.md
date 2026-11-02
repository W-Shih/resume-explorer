# Issue-5 — Explorer 多 Process／生命週期：RCA 與有條件修復計畫

- **Reviewed:** 2026-11-02
- **Status:** Proposed / RCA Required；**尚未實作，也未證實是本程式 Bug**
- **Priority:** P2（若證實資源耗盡或核心可靠性問題，重新評估為 P1）
- **Repository:** `E:\_projects\tools\scripts\resume-explorer`
- **Tracker:** [`../Backlog.md`](../Backlog.md) — Issue-5 under Open Issues
- **Historical incident, NOT this issue:** [`resume-explorer-Issue-5-drivefs-shell-hang-rca.md`](resume-explorer-Issue-5-drivefs-shell-hang-rca.md)，該檔保留舊檔名，但內容為 **Issue-6 / Closed (Mitigated)** 的 Google Drive／Explorer Hang RCA。
- **Review baseline:** 撰寫時 repo HEAD 為 `43cee24`；先前離線測試在較早的 `2f3a361` 下執行，開始新調查時須記錄最新 Commit 並重跑 Baseline。

> **硬性原則 — RCA first, no blind fix:** Phase 0–2 先確認是否存在真缺陷、收集唯讀證據並建立控制變因重現。若尚未能解釋異常，就先在可重設的隔離 Windows 測試環境進行必要的互動式 Debug（Breakpoints / Tracepoints、Process creation/exit、HWND/PID 對照及例外路徑），**定位具體的可重現錯誤機制後，才考慮修改正式 Restore 程式碼**。不能因看到很多 `explorer.exe` 就直接加入 Process cleanup、Kill Explorer、改變視窗合併語意或盲目重構 COM。

## 1. Review 結論、事實及責任界線

### 1.1 已觀察到的事實

1. 另一個專案 `restart-win-explorer-scripts/scripts/restart-file-explorer.bat` 的 `taskkill /f /im explorer.exe` 曾回報終止 **38 個 PID**。不同時刻另一份唯讀觀察顯示 **9 個 Explorer Process**；沒有可比的「開始前／完成後／穩定後」配對資料。
2. 這些數量**不能證明 Process Leak、Memory Leak 或由 `resume-explorer` 建立**；正常 Windows Shell 架構、每視窗隔離、既有視窗、其他工具及第三方元件仍可能解釋差異。
3. `resume-explorer.ps1` 當前對外提供 `Capture`、`Preview`、`Restore`、`PreviewRetry`、`Retry`，**沒有 `Restart` Action**。不能把另一個專案強制重啟 Explorer 的行為歸因給本程式。
4. `Restore` **有意新增** Explorer 視窗：每個含有效 Path 的 Snapshot Group 可有一次 `OpenWindow` 請求。使用者重複執行完整 Restore 本來就可能新增視窗／Tabs，不等於程式內意外重複呼叫。
5. `Retry` 是對使用者確認的現存 HWND 進行 Tab 補做；目前設計不為 Retry 建立新視窗。
6. **Issue-6 已拆分並緩解**：其 `Not Responding` 與 `drivefsext.dll → WaitNamedPipeW`、Quit Google Drive 後恢復有觀測上的關聯，但根因仍未證實，**目前沒有證據顯示由 `resume-explorer` 造成**。Issue-6 的恢復不代表 Issue-5 已修復，亦不是 Issue-5 Process Leak 的證據。

### 1.2 要確認的真正問題

| 分類 | 操作性定義 | Issue-5 的處理 |
| --- | --- | --- |
| Expected Process Growth | Explorer Process 隨正常視窗、Shell 行為或有意 Restore 而增加 | 建立基準；不是 Bug |
| Unexpected Window Creation | 同一次 Restore 在不應再次建立時，送出額外視窗建立請求，或產生非預期視窗 | 定位具體建立路徑，若由本程式造成才修復 |
| Unclassified Persistent Process | 關閉測試視窗並等待穩定後，仍有無法判明角色的 Process | 收集生命週期／Handle 證據；**未知不等於 Leak** |
| Confirmed Program-Related Leak | 相同受控條件可重現持續的非預期 Process 增量，且已取得將其連到本程式行為的證據 | 進入最小修復階段 |
| UX: repeated Restore duplicates windows | 重複執行有意新增更多 Window／Tab，但不符合使用者期望 | 可獨立開 Feature Request；不等同 Process Leak |

**不可使用 `MainWindowHandle = 0` 作為孤立 Process 的充分條件；不可預設 Process、頂層 Window、Tab 或 `Start-Process` 請求是一對一。**

## 2. 程式碼盤點與風險邊界

以下行號是 2026-11-02 審查快照，後續若有 Commit 變動請以函式名稱重新定位。

| 位置 | 目前行為 | RCA 焦點 |
| --- | --- | --- |
| `resume-explorer.ps1` | Action 限於 Capture、Preview、Restore、PreviewRetry、Retry | **沒有 Restart**；排除錯誤歸因 |
| `resume-explorer.core.ps1:65` `Get-ExplorerObservation` | 使用 `Shell.Application.Windows()` 列舉 Views | View 數量非 Process 數；COM 觀測可能慢或阻塞 |
| `:27` `Get-WindowFingerprint` | 檢查 HWND、Root HWND、PID、Process StartTime、SessionId | PID 重用與 RootHwnd / RawHwnd 對應 |
| `:109` `New-ExplorerAdapter` | `OpenWindow` 呼叫 `Start-Process ...\explorer.exe`（`-WindowStyle Normal`） | 實際視窗／Process 可能由既有 Shell Process 承載；不是以 Start-Process PID 判定完成 |
| `:336` `Wait-NewExplorerWindow` | 用已知 RootHwnd、Path、穩定觀測確認候選，輪詢期限 12 秒 | 延遲出現、超時、同 Path 歧義及錯誤配對 |
| `:484` `Invoke-RestoreGroups` | 每個有效 Group 最多一次 OpenWindow；副作用前寫 `WindowCreateAttempted` checkpoint | 函式在 exception／timeout 後是否保持未知結果、不重送；是否有其他建立呼叫路徑 |
| `:539` `Start-RestoreRun` | 根據 Snapshot Groups 建 Run 後啟動 Restore | 重複完整 Restore 的預期語意 |
| `:627` `Start-RetryRun` | 指定既有 `TargetHwnd`，驗證 Fingerprint 後新增所選 Tab | 不應透過 Retry 產生新 Window；保留 Replay Safety |

Windows 「Launch folder windows in a separate process」設定、Shell Process、Explorer 視窗及 Tabs 的映射可能因 OS／設定而不同。`Shell.Application.Windows()` 回傳 Shell Windows Collection，並非 `explorer.exe` Process Inventory；它們要分開量測。`Start-Process` 發出的請求也不保證該 PID 就是最後持有視窗的 PID。

## 3. 假設、優先順序與判斷證據

| 假設 | 目前證據等級 | 控制變因／判定方式 |
| --- | --- | --- |
| H1：正常的 Windows 多 Process／視窗隔離 | 合理，未驗證 | 記錄 Windows 版本／Separate Process 設定及 Session 內 PID ↔ HWND ↔ Tab |
| H2：重複 Restore 按設計新增視窗 | 程式碼支持 | Run 次數、有效 Group 數、每次 OpenWindow 次數、實際新視窗對照 |
| H3：OpenWindow 已成功，卻未在 12 秒內被確認 | 合理風險，未驗證 | `WindowDetectionTimeout`、之後才出現的 Root HWND、下一次 Restore 是否造成重複 |
| H4：特定分支意外重複呼叫 OpenWindow | 尚無證據 | Mock 次數、Checkpoint 失敗、Exception、Ambiguous、Timeout 的 Unit Tests |
| H5：異常持續累積的 Explorer Process | 尚無證據 | 正常關閉測試視窗前後 PID Creation/Exit、穩定期趨勢 |
| H6：其他工具／Shell／第三方元件啟動 Explorer | 未排除 | **不執行本工具**的控制組與 Process creation/exit trace |

**優先順序：H1 → H2 → H3 → H4／H5 → H6 交叉驗證。** 若 H1／H2 已能充分解釋觀測，直接記錄並結案為非缺陷；不能為了有修復 Commit 而修改程式碼。

## 4. Phase 0 — 安全基準、缺陷定義與 Baseline

1. 記錄 repo Commit、OS Build、Windows Session、PowerShell 版本、Explorer Separate Process 設定、測試 Snapshot（Group／Tab 數）、現有 Explorer 視窗數。
2. **唯讀優先**：先盤點現有 Process、Windows 與 Tabs，不在日常桌面執行新的 Restore；不觸發 `taskkill /f /im explorer.exe`。
3. 記錄現有 Console、Run Report 及歷史 38／9 PID 觀察的不同時間／環境；不能合併成一條量測趨勢。
4. 重跑既有無 GUI 測試作為目前版本基準：
   - `tests/Issue2.Tests.ps1`：先前 `2f3a361` 基準為 **39 / 39 Passed**，當前版本需重新確認。
   - `tests/RestoreSummary.Tests.ps1`：先前 **S01–S15 Passed，S16 assertion failed，S17 未執行**。記錄為獨立的既有測試異常；不可宣稱與 Process Leak 有關，亦不可隱藏。
5. 定義所有「增加」都必須給出同 Session、相同 Setup 的 `Before`、`AfterRequest`、`AfterSettled`、`AfterNormalClose` 四個取樣點。
6. 保存敏感性最低的彙總紀錄；原始完整 Path、CommandLine、個人報告與 Dump 不提交 Git。

**Phase 0 Gate：** 已定義 expected / unexpected / unknown，版本和測試結果可追溯，並完成 Issue-5 與 Issue-6 的證據切分。

## 5. Phase 1 — 建立唯讀 Process／Window／Tab Inventory

### 5.1 設計：將診斷與 Restore 分離

可評估獨立的 `diagnostics/Get-ExplorerProcessInventory.ps1` 或等價的唯讀模組（名稱為候選，不是既有實作）。**Phase 1 可以新增隔離的診斷程式，但不得直接改變 Restore 的副作用或流程**。

分開擷取四種維度：

- **Process:** PID + CreationTime（共同做 Process Identity）、SessionId、ParentPID、CPU、WorkingSet、PrivateBytes、HandleCount；ParentPID 不代表故障歸屬。
- **Window:** `EnumWindows`、`GetWindowThreadProcessId`、`GetAncestor`、`IsWindowVisible`；保存 HWND → PID、Root HWND 及可見性。不要推論不可見 Window 一定為 Leak。
- **Tab / Shell View:** 獨立、**可選**的 `Shell.Application.Windows()` 列舉，加上 RawHwnd、RootHwnd、PID、Tab Identity 和不含私密路徑的統計。Shell COM 可能同步卡住，故**不得讓基本 Process／Window Inventory 等待 COM 才能完成**。
- **Creation Request / Run:** 同步比較 Restore RunId、GroupIndex、`WindowCreateAttempted`、ReasonCode、各組 `OpenWindow` 請求次數（初期使用 Mock／Trace；是否加入正式 Report 須另評估相容性）。

基本唯讀命令（只作為手動診斷起點）：

```powershell
Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" |
    Select-Object ProcessId, ParentProcessId, SessionId, CreationDate

Get-Process explorer -ErrorAction SilentlyContinue |
    Select-Object Id, StartTime, SessionId,
                  MainWindowHandle, HandleCount,
                  WorkingSet64, PrivateMemorySize64
```

### 5.2 比對規則與資料格式

- Process Identity = `PID + CreationTime + SessionId`；PID 相同但建立時間不同視為不同 Process。
- 觀察 **新建、退出、現存與未知分類**，而非只算 `taskkill` 看到的總 PID。
- Windows 根視窗歸類要以 HWND + PID + 觀測時間為基礎；HWND 也可能被重用。
- 不可將「沒有在 Shell COM Collection 出現」自動歸類為「沒有有效 Shell 角色」。
- 記錄 Observation 的來源與可靠性；若 COM 超時／不完整，標記 `Unknown`，**不當作 0**。診斷程序不得對同一個可疑 Process 重複阻塞呼叫以補空值。

建議的 **示例 Schema（數值僅供格式演示，不是真實測量）**：

```json
{
  "phase": "AfterRestoreSettled",
  "runId": "example-run",
  "sessionId": 1,
  "processCount": 9,
  "windowCount": 7,
  "tabCount": 18,
  "windowCreateRequests": 4,
  "newProcessIdentities": 4,
  "unclassifiedProcesses": null,
  "comObservation": "Unknown",
  "isSampleData": true
}
```

**Phase 1 Gate：** 能解釋新 PID 與 Windows／Shell 角色的關係，或誠實標示未知；產出的診斷資料足以讓另一個工程師重現分析，並且不會因觀察本身啟動或 Kill Explorer。

## 6. Phase 2 — 控制變因實驗及必要時互動式 Debug

### 6.1 測試環境與守則

- 優先在**可重設、具有互動桌面的獨立 Windows VM** 執行有副作用的 Restore／Close。先取得明確測試 Snapshot，保證沒有實際使用者未儲存工作。
- 先測「不使用本工具」控制組，再測 Capture／Preview，再測最少 Group Restore；比較相同 OS／Session／Separate Process 設定。
- 先收集 Before → AfterRequest → AfterSettled → AfterNormalClose；若出現未知結果，**不要立刻重複 Restore**。
- 不在日常 Dell PC／Horizon VDI 大量建立測試視窗；不用 `taskkill` 來重設基準，不關閉非測試所建立的視窗。
- 所有 PID、TID、HWND 都是當次樣本，不當作跨次固定識別。

### 6.2 測試矩陣

| ID | 操作 | 必須回答／驗證 |
| --- | --- | --- |
| T01 | 不執行本工具，正常操作 Explorer | Windows 自然 Process churn 基準 |
| T02 | Capture／Preview | 本程式無明確 OpenWindow 請求 |
| T03 | Restore 1 Group / 1 Tab | 最多一次 OpenWindow Request；辨識其視窗及 Process |
| T04 | Restore 3 Groups / 多 Tabs | 每有效 Group 最多一次 OpenWindow；記錄 Tab 和 Window 數，不假設 PID 一對一 |
| T05 | Retry 已確認的 TargetHwnd | `OpenWindow = 0`；Tab Side Effect 不重送 |
| T06 | **另一次完整 Restore** | 新增視窗屬預期行為還是產生非預期額外請求 |
| T07 | 以正常 Close 關閉測試視窗 | PID／HWND 在穩定期後是否仍有不合理累積 |
| T08 | Mock WindowDetectionTimeout / late arrival | `OutcomeUnknown`、不自動重送視窗建立 |
| T09 | 分別測試 Separate Process 設定 | 比較 OS 原生 Process／Window 映射差異 |
| T10 | 第三方或 Windows Shell 也同時開視窗 | 不可把其他建立者的新視窗錯認成自己的 |

### 6.3 Interactive Debug Gate（若數據仍不足，**先 Debug，後 Fix**）

符合以下任一情況，就以最小測試案例進入 Debug，而不是猜測性修改正式邏輯：

1. 同一個 Restore Run 的 Process／Window 增量明顯超出預期，卻無法說明對應呼叫；
2. `WindowDetectionTimeout` 之後才有目標視窗出現，且下一輪 Restore 可能造成重複；
3. 關閉受控測試視窗後仍持續出現無法分類的異常 Process；
4. Console／Run Report 的 `WindowCreateAttempted`、實際 Start-Process 請求與 HWND 觀測互相矛盾。

建議互動式 Debug 步驟：

1. 在隔離 VM 的 PowerShell／VS Code Debugger 中，對 `Invoke-RestoreGroups`、`Adapter.OpenWindow`、`Wait-NewExplorerWindow` 及其 Exception／Timeout 分支加 Breakpoints 或 Tracepoints；每次記錄 RunId、GroupIndex、呼叫次數與時序。
2. 同時使用 Process Explorer／Process Monitor（若可用）或 Windows Process creation/exit 診斷，配對 PID + CreationTime，追蹤 HWND 映射。**不要單以 Parent PID 或 Start-Process 的返回 PID 推論最終 Explorer 視窗歸屬。**
3. 對 `Known RootHwnd`、Path matching、`seen` 候選、`WindowAmbiguous`、`WindowDetectionTimeout`、`WindowCreateOutcomeUnknown` 取得一條具體執行 Trace。
4. 能安全重現時，進行單一控制變因 A/B；仍無法重現就保存觀測與不確定性，**不可假裝完成 RCA**。
5. 若證據只顯示預期 OS／Restore 行為，直接轉入 Not-a-Defect 結案；若證實本程式有缺陷，才進 Phase 3 的最小修復。

**Phase 2 / RCA Gate：** 明確回答「真缺陷或正常行為？多出來的 Process 誰建立？哪個呼叫／競態／錯誤分支可以重現？」若缺少上述證據，狀態維持 Open / Investigating；**禁止進入猜測性修復**。

## 7. Phase 3 — 根據 RCA 結論選擇最小修復（條件性）

### Case A — 全部可由正常 Windows／Restore 行為解釋

- 不改任何正式 PowerShell 程式碼。
- 在 README 說明 Restore **只新增，不取代**既有 Explorer 視窗；反覆執行完整 Restore 可能增加視窗和 Process，Windows 可能採隔離架構。
- 附上控制組及 Process／Window 對照資料，將 Issue-5 結案為 **Closed (Not a Defect)**。

### Case B — 重複 Restore 的 UX 不符合使用者預期，但沒有 Leak

- 不將 UX 需求偽裝為 Process Leak；必要時另開 Feature Request。
- 可評估**可選**的 `PreviewRestore`／建立前差異預覽，但這是設計提案而非當前 Issue-5 修復條件。
- **不可因 Path 相同就擅自合併、重用、跳過**不同 Snapshot Groups；重複 Path 可能是刻意開啟的多視窗／多分頁。

### Case C — 建立視窗已發生，但確認流程逾時或發生歧義

- 先分析 `Wait-NewExplorerWindow` 12 秒觀測與同步 Shell COM 的實際耗時；考慮 Issue-4 的同步阻塞邊界，不能只把 Timeout 調大。
- 必要時增加**低成本且可關閉**的 Window Request → Observation 診斷，保留原子 Checkpoint 和不明結果。
- Timeout／Exception 後持續 `OutcomeUnknown`，不可因未觀測到視窗就自動再次 `OpenWindow`。
- 新的人工復原流程必須重新 Snapshot／Preview 並驗證身份；未經同意不得自行 Close 可疑視窗。

### Case D — 證實本程式造成異常持續 Process 累積

- 按具體 Trace 查找真正擁有責任的 Start-Process、COM／UIA 生命周期、失敗分支或長期 Worker；每次修復限於已證實的失效機制。
- 必須先用 Regression Test 證明缺陷，再實作修補並重新執行同一控制案例。
- **禁止**把大量 `FinalReleaseComObject()`、盲目 Kill 不可見 PID、強制重啟 Explorer 或改變 Restore 分組語意當成泛用解決方案；可能破壞有效 Shell 物件或使用者工作階段。

## 8. Automated Tests 與 E2E 策略

建議新增 `tests/Issue5.ProcessLifecycle.Tests.ps1`（候選檔名），優先沿用現有 Adapter + Fake Clock／Mock；**不需要真實 Explorer、UIA 或管理員權限即可跑 Unit Tests**。

| Unit Test | 必須滿足 |
| --- | --- |
| 單 Group Restore | 最多一次 `OpenWindow`，輪詢不得觸發第二次 |
| 多 Group Restore | 每有效 Group 最多一次請求；按原 Group 順序記錄 |
| Invalid Path / Empty Group | 無效項目不建立視窗，保留原索引 |
| OpenWindow Exception | `OutcomeUnknown`；保留 `WindowCreateAttempted`；不重送 |
| Late Arrival / Timeout | 不因超時再次開窗；觀測結果維持保守 |
| 同 Path 多候選 / Root HWND 歧義 | 回報 `WindowAmbiguous`，不能猜選 |
| Retry existing fingerprint | `OpenWindow = 0` |
| PID 重用／Process Replacement | `PID + CreationTime + SessionId` 比對，拒絕 stale 身分 |
| 其他外部建立者同時啟動 Explorer | 不應以 Path 一致就認領所有候選 |
| Checkpoint 失敗 | 在副作用前失敗時，`OpenWindow = 0` |
| Diagnostic disabled / enabled | 不更改 `Status`、`ReasonCode`、`Invoke/Navigate` 次數 |
| 舊 Run Report / Retry family | 保留 Schema、Checkpoint、PreviewRetry 與 Retry 相容性 |

隔離 E2E：不同 Window 數與 Tabs 數、不同 Separate Process 設定、WindowDelay、同 Path、異常 Shell COM、Close 後穩定期；觀察 Process Churn 與恢復，而非只看總 PID。Hosted GitHub Actions Windows runner 適合無 GUI 的 deterministic tests，**不可預設其支援可重現的互動式 Explorer E2E**。

## 9. Acceptance Criteria、結案狀態與安全原則

### Correctness

- 每個有效 Group 最多一次 `OpenWindow`；Retry 不主動建立新視窗。
- 不以相同 Path、單一 PID 或 Root HWND 變化作為成功的充分條件。
- 保留 `WindowCreateAttempted`、`OutcomeUnknown`、原子 Checkpoint、Fingerprint、Single Invoke / Navigate、明確 PreviewRetry / Retry。
- 不重新引入 Issue-2 的 `-WindowStyle Hidden` / Verified-but-invisible regression。

### Lifecycle / Evidence

- 同一 Session 裡能提供 Before／AfterRequest／AfterSettled／AfterNormalClose 的 Process／Window／Tab 及請求次數。
- 能列出新 Process 的可能角色，並將未分類的記為 Unknown，不能誤報確定孤立／Leak。
- 若聲稱已修復 Program-Related Process Leak，須在隔離 VM 重現修復前的缺陷，並證明修復後同條件下不再持續產生額外 Process。
- 不強制要求 Shell 正常關閉視窗後立刻回到完全相同的 PID 清單；允許 Windows Process 生命週期有自然延遲。

### Safety / Privacy

- 不為診斷自動 `taskkill /f /im explorer.exe`，不清理未知 PID，不關閉日常使用者視窗。
- 不對個人 PC／VDI 進行大量 Restore 壓測；不因 E2E 失敗犧牲尚未儲存工作。
- 不持久化敏感 Path／CommandLine／Dump 至 Git；診斷須有可觀測的失敗狀態與上限。
- 不因 Issue-6 Google Drive Hang 就修補本程式；只有共同可重現機制出現時才重新評估兩者關聯。

### 結案決策

| 證據結果 | Issue-5 狀態 |
| --- | --- |
| Windows／Restore 預期行為充分解釋 | **Closed (Not a Defect)** |
| 證實本程式 Bug，已完成最小修補與驗收 | **Closed (Fixed)** |
| 可重現異常但尚未定位根因 | **Open (RCA in Progress)**，按影響重排優先級 |
| 無法重現且證據不足 | **Open (Unconfirmed)**；或明確記錄限制後行政結案，不能寫成 Fixed |
| 僅有使用體驗上的新增視窗預期不同 | 將 Process Leak 類別結案，另列 Feature Request（若有需求） |

## 10. 建議工作分解與 Commit 切分

| 順序 | 工作 | 建議 Commit／交付物 |
| --- | --- | --- |
| 1 | 建立本 Issue-5 獨立 RCA 計畫，Backlog 連結（僅文件） | `docs(issue5): add explorer process lifecycle investigation plan` |
| 2 | 建立唯讀 Process／Window Inventory 與資料模型 | `feat(issue5): add read-only explorer lifecycle diagnostics` |
| 3 | 加入 Mock／Adapter Regression Tests | `test(issue5): cover window creation and process lifecycle` |
| 4 | 在隔離 VM 執行控制變因實驗，必要時 Interactive Debug | 保存匿名化 RCA 證據；**不預設有修復 Commit** |
| 5 | **僅在 RCA Gate 通過、證實程式缺陷後**進行最小修復 | `fix(issue5): <specific-root-cause>` |
| 6 | 無 GUI 測試、隔離 E2E、前後比對、更新 README／Backlog | `docs(issue5): record evidence and resolution` |

**禁止提前跳到第 5 步。** Phase 0–2 與必要的 Interactive Debug 沒有產生可重現的本程式缺陷證據時，不能盲目重寫程式、強制 Kill Process 或加大 Timeout 以假裝修復。

## 11. 與其他 Issue 的明確分工

- **Issue-2（已完成核心實作）**：保留身份安全、Checkpoint、單次副作用與 Visibility 的 Regression 防護。
- **Issue-3**：前景／焦點是否影響 Tab 操作屬另一個維度；如有資料交叉使用，須有控制變因。
- **Issue-4**：同步 Shell COM／UIA 超時屬專門的 Deadline/RCA 問題。若 Issue-5 觀察到被 COM 阻塞，只共享 Timing 證據，不能直接推導 Process Leak。
- **Feature Request-6**：精簡大 JSON Report；若加入 Issue-5 診斷，須限制樣本容量且不重複保存敏感 Views。
- **Issue-6 (Closed / Mitigated)**：Google Drive Shell extension／Explorer `Not Responding` 事件；其歷史文件仍叫 `resume-explorer-Issue-5-drivefs-shell-hang-rca.md`。這**不是** Issue-5 的修復計畫，亦**沒有**證據顯示 `resume-explorer` 造成當次 Hang。
- **`restart-win-explorer-scripts`**：`.bat` 使用 `#` 註解造成 CMD `'#' is not recognized` 是另一專案的語法問題，**不是** Process Leak 根因；不在本 Issue 擅自修改。

## 12. 文件與作業約束

- 本文件是 **Proposed Investigation Plan**，不表示 Phase 0–3 已完成、根因已發現或程式已修復。
- 在 `Backlog.md` Issue-5 中保留精簡摘要、RCA-first Gate 及本計畫連結。
- 保留 Issue-6 的歷史 Google Drive RCA 文件及 Skill，避免切斷事件交接。
- 調查者開始執行前應確認新的 HEAD／Git 狀態；不得覆蓋既有未提交改動。
- 本次文件工作只應改動 Markdown；**不對實際 Explorer 執行 Capture、Restore、Restart、Kill 或 E2E**。
