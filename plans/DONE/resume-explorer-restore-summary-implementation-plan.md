# Resume Explorer — Restore Result Summary & Unverified Item Diagnostics 實作計畫

- 日期：2026-11-01
- 狀態：**Done — implementation complete (2026-11-01)**
- Implementation commit: `319da25`
- Validation: 39 existing Issue2 tests + 17 new RestoreSummary tests passed in PowerShell 7.6.1; see `ISSUE2-VALIDATION.md` (repository root).
- 適用版本：目前的 `0.1.0-beta.1+issue2` 候選版
- 專案：`E:\_projects\tools\scripts\resume-explorer`
- 優先度：P1；建議作為 Issue-2 後續的獨立、低風險 observability enhancement
- 本文件目的：定義實作規格、程式變更、測試矩陣、驗收及回滾；不宣稱 Issue-2 已完成實機驗收

## 1. 決策摘要

**實作**兩項 enhancement，合併交付為「Restore Result Summary & Unverified Item Diagnostics」：

1. Restore／Retry 結束時，對**每個非 `Verified` 項目**列出原始 Group、Tab（`ItemIndex`）、路徑、`Status` 與有值的 `ReasonCode`。
2. 提供明確的 `Total / Verified / Not verified` 統計、完成狀態、原始 Report JSON 路徑，以及有未驗證項目時可複製執行的 `PreviewRetry` 指令。

**原則：只改善結果呈現，不改變 Restore 的行為或安全界線。** 以既有 `Run.Items` 與 Report Path 作為資料來源；不改 JSON Schema、不新增第二份 log、不自動重試、不猜測哪個 Explorer Tab 成功。`Completed` 仍表示執行流程已結束，**不表示全部還原成功**。

## 2. 已核對的現況與缺口

| 位置 | 現有行為 | 本次方向 |
| --- | --- | --- |
| `resume-explorer.ps1` | `Restore`、`PreviewRetry`、`Retry` 透過 core dispatch | **不新增 CLI 參數、不改 dispatch** |
| `resume-explorer.core.ps1` / `New-RestoreItem` | 已記錄 `GroupIndex`、`ItemIndex`、`RequestedPath`、`Status`、`ReasonCode` 等欄位 | **直接重用欄位** |
| `Write-RunSummary($Run,$Path)` | `Report: <path> (<State>)`，再列出實際出現的 Status 計數 | 擴增固定欄位、逐項明細和警告 |
| `Complete-Run` | 正常結束為 `Completed`；例外時 `Aborted`；`finally` 先存 checkpoint，再呼叫 summary | **保留狀態、例外與 checkpoint 語意** |
| `Show-RetryPreview` | 讀取 Report、列舉現存 Explorer target、顯示全部項目、寫出 `.retry-preview.json` | **不改其行為**；提示必須正確描述它會列舉並寫檔 |
| `Start-RetryRun` | 明確選 Group/Item/HWND；不確定的項目需 `-IncludeUncertain` | **不修改 Retry 安全檢查** |
| `ISSUE2-VALIDATION.md` | `Diagnostics.Samples` 已包含在單一 JSON report | **Report JSON 就是詳細診斷記錄** |

目前可能看到 `Report: ... (Completed)` 和 `Verified: 15` 等統計，卻不知道哪幾個 Group / Tab 尚未完成；`Completed` 也容易被誤讀為全部成功。原先 18 個 `Verified` 但 Explorer 視窗不可見的 regression 提醒我們：**`Verified` 僅是現有的身分／路徑驗證，不是視窗可見性驗證**。

## 3. 範圍與非目標

### In scope

- Restore 與 Retry **共用**相同的結果摘要（兩者都會經過 `Complete-Run`）。
- 明確列出所有 `Status -ne 'Verified'` 的項目，不限於已嘗試過的 Tab。
- 原始 Group / Item 索引保持不變；路徑重複時仍分別列出。
- 可讀的完成、部分未驗證、中止、空結果四種狀態。
- 有非 Verified 項目時，產生 Warning 和完整的 Report 路徑／PreviewRetry 指令。
- 純函式結果分析與 Console 渲染拆開，增設離線測試及 README 範例。

### Out of scope（明確禁止在本次順手修改）

- 不更改 `Invoke-RestoreGroups`、`Invoke-TabTransaction`、偵測／導覽／重試的 timeout、候選身分判定及 UI Automation 行為。
- 不新增或重送 `AddButton / Invoke`、`Navigate2`；不因 warning 自動 Retry。
- 不改 `Run.State` 既有的 `Completed`／`Aborted` 定義。
- 不修改 `SchemaVersion=1`、Report JSON 欄位、報告路徑與現有 Retry 家族的持久化規則。
- 不新增 log 檔、GUI、視窗可見性檢查、ZIP/Shell namespace 支援、背景／不搶焦點還原。
- 不主動啟動 Explorer 或執行實際 Restore 作為這次實作的基本測試。

## 4. 使用者可見輸出規格

### 4.1 有未驗證項目：主要案例（數據為示意）

```text
Report: C:\Users\Example\AppData\Local\ResumeExplorer\Runs\abc123.json (Completed)
Restore summary:
  Verification: Partial
  Total: 18
  Verified: 15
  Not verified: 3
  OutcomeUnknown: 1
  NotAttempted: 1
  SkippedInvalidPath: 1

Unverified items:
  Group 2:
    Tab 3 | OutcomeUnknown | AmbiguousCandidates
      Path: D:\Work\Project\Notes
    Tab 4 | NotAttempted
      Path: D:\Work\Project\Reports
  Group 5:
    Tab 1 | SkippedInvalidPath | InvalidPath
      Path: H:\Missing\Project

WARNING: 3 of 18 items were not verified.
Review retry options:
  & 'E:\_projects\tools\scripts\resume-explorer\resume-explorer.ps1' -Action PreviewRetry -ReportPath 'C:\Users\Example\AppData\Local\ResumeExplorer\Runs\abc123.json'
```

輸出順序：**保留既有 `Report: <path> (<State>)` 作為第一行**；其後 summary、非 Verified 明細、Warning、PreviewRetry。Status 統計只印有出現且數量非零的**非 Verified**類型，固定優先順序：`OutcomeUnknown`、`PreconditionFailed`、`NotAttempted`、`SkippedInvalidPath`；若未來出現其他狀態也不得被漏算。`Verified` 只在固定總結行列一次。

### 4.2 全部驗證完成

```text
Report: C:\...\Runs\abc123.json (Completed)
Restore summary:
  Verification: Complete
  Total: 18
  Verified: 18
  Not verified: 0

All 18 items verified.
```

不列 `Unverified items`，不顯示 `PreviewRetry`，也不產生未驗證警告。請勿將 `All items verified` 寫成「所有 Explorer 視窗可見」或「完整恢復工作階段」。

### 4.3 流程中止（`State=Aborted`）

即使某些項目已 `Verified`，仍須顯示 `Verification: Interrupted`、實際各項目數量及非 Verified 明細；另有 `WARNING: Restore run aborted; inspect the report and error before retrying.`。**禁止**輸出 `All ... verified` 作為整次 run 的成功結論。保留原始例外的傳遞與 PowerShell 失敗結果，不因列印摘要吞掉例外。

### 4.4 空 Snapshot 或零項目

`Total: 0`、`Verified: 0`、`Not verified: 0`、`Verification: Empty`；顯示 `No restore items were found.`。不要誤報 `Complete` 或「0 個未驗證所以全部成功」，也不提供無意義的補做指令。

### 4.5 用詞及語意

| 用詞 | 精確定義 |
| --- | --- |
| `Total` | 本次 run 的 `Run.Items` 數量；Retry 子 run 僅計算本次被選取的項目 |
| `Verified` | `Status -eq 'Verified'`；不額外推論桌面可見性 |
| `Not verified` | `Total - Verified`；包含未知或未嘗試狀態 |
| `Partial` | `Completed`、`Total > 0`，但非全部 `Verified`；即使 `Verified=0` 亦屬此類 |
| `Interrupted` | `Run.State = 'Aborted'`；優先於計數推算 |
| `OutcomeUnknown` | 操作可能已發生，但尚未確認；不是「肯定失敗」 |
| `NotAttempted` | 尚未送出該項目的建立請求；不能當作已建立 |
| `SkippedInvalidPath` | 目前路徑無效／不可存取；應先修正條件再考慮補做 |

## 5. 建議程式結構

### 5.1 純結果分析：`Get-RunSummary($Run)`（新增）

**輸入**：記憶體中的 `Run`；**輸出**：單一唯讀用途的 summary object；不寫磁碟、不呼叫 Shell/UIA、不改 `Run.Items`、不呼叫 `PreviewRetry`。

建議欄位：

```powershell
[pscustomobject]@{
    State           = $Run.State
    Verification    = 'Complete' # Complete | Partial | Interrupted | Empty
    Total           = 18
    Verified        = 15
    NotVerified     = 3
    StatusCounts    = $counts  # 按 Status 計數；含未知值
    UnverifiedItems = $unverifiedItems
}
```

演算法（可直接轉成 PowerShell 5.1 相容程式）：

1. `$items = @($Run.Items)`；絕不以路徑去重或重新編號。
2. `$unverified = @($items | Where-Object { $_.Status -ne 'Verified' } | Sort-Object GroupIndex, ItemIndex)`。
3. `$total = $items.Count`；`$verified = $total - $unverified.Count`；`$notVerified = $unverified.Count`。
4. 建立 StatusCounts；`null`／空白 Status 視為 `Unknown`（仍屬未驗證），不得因缺欄位當成 `Verified`。
5. `Run.State='Aborted'` → `Interrupted`；否則 `Total=0` → `Empty`；否則 `NotVerified=0` 且 `State='Completed'` → `Complete`；其餘 → `Partial`（若出現其他未知 run state，應標示為非完整或未知，不宣稱成功）。
6. 回傳 summary object，讓渲染及測試使用同一套邏輯。每次對整個 run 進行一次分析，避免逐 Group 重算。

### 5.2 渲染：擴增 `Write-RunSummary($Run,$Path)`

- 呼叫 `Get-RunSummary`；保留原始首行 `Write-Host "Report: $Path ($($Run.State))"`，確保既有人工使用流程較易相容。
- 以固定欄位及順序輸出總數、驗證結果；依 `GroupIndex` → `ItemIndex` 升序列出所有非 Verified 項目。
- 有 `ReasonCode` 才附加 `| <ReasonCode>`；路徑獨占一行、不得省略或縮寫，方便手動搜尋。
- 欄位內容若出現 CR/LF、TAB 或控制字元，渲染時跳脫為可見文字，避免外部編輯過的 JSON／Snapshot 汙染終端行結構；**不修改原始 Report 值**。
- 對 `NotVerified > 0` 發出 PowerShell 警告。建議 `Write-Warning -WarningAction Continue`，使其使用 native Warning stream，且不因呼叫端 `WarningPreference='Stop'` 破壞已完成的 Restore。
- `Aborted` 另外警告；不得將「未驗證」直接稱為「失敗」。
- 僅在需要檢查未驗證項目時提供 `PreviewRetry`。使用**完整的入口腳本路徑**（可從同目錄解析），以及完整 `ReportPath`；PowerShell 單引號內的 `'` 需轉成 `''`，避免含空白／單引號路徑無法直接複製執行。
- 若要保留使用者原先習慣的簡寫，可在文件中另示 `.\resume-explorer.ps1 -Action PreviewRetry ...`，但終端預設最好輸出可從任意工作目錄執行的完整命令。
- 不使用 `Format-Table` 顯示未驗證路徑，避免欄位截斷；不為此增加新的 Action 或可設定開關。

### 5.3 `Complete-Run` 的相容性保護

原有 `try/catch/finally`、副作用前 checkpoint、原子寫入、`throw` 必須保留；本 enhancement 優先僅增加 summary 函式並沿用現有呼叫點。特別驗證：

- 任一 Restore transaction 失敗而**沒有**整體例外時，`Completed` 仍可伴隨 `Partial`。
- 整體例外時，`Aborted` 及原始錯誤必須持續往外傳，摘要不得改寫 `Run.State` 或吞掉例外。
- 最終 checkpoint 寫入失敗時，現有 warning／in-memory JSON fallback／例外必須保留。若擴充顯示持久化狀態，可傳入選用的 `FinalCheckpointSaved` 旗標，讓摘要標示「Report may be stale」；**不得聲稱磁碟中的 Report 一定是最新**。
- 報告檔在 `Initialize-RunPath` 之前就建立失敗時，不應產生虛假的 `Report:` 路徑或假裝還原有執行。
- Summary 不能新增任何 Explorer 操作，亦不應因列印錯誤改變原本的 CLI exit/error behavior。

## 6. Retry 與 Report 的正確性

- `Report:` 指向**當次 run** 的 JSON；`Retry` 可能建立 `RetryRuns\<ChildRunId>.json`，不是直接修改原始 Report。
- Child run 的 `Total` 只計算此次 selected items，**不**宣稱整個原 Snapshot 已全部修復；要看整個 run family，仍應使用原 Report 及既有子報告規則。
- `PreviewRetry` 不只是打開文字 log：它會列舉**目前**的 Explorer target，並在 Report 旁建立 `.retry-preview.json`。提示用語為 `Review retry options`，不得寫成「純讀檔」。
- `PreviewRetry` 自身可能因 Shell 不可用失敗，但使用者仍可以讀取 JSON Report；因此警告不能宣稱 PreviewRetry 一定會成功。
- `OutcomeUnknown`、`InvokeAttempted`、`NavigateAttempted` 或 `WindowCreateAttempted` 都不可以被自動補做；保留既有 `-IncludeUncertain` 明確授權及重複執行保護。
- 不新增基於相同 `RequestedPath` 的成功推定；不將 `NotAttempted`／`SkippedInvalidPath` 強行標為 `Failed`。

## 7. 自動化測試計畫（無真實 Explorer 操作）

延續 `tests/Issue2.Tests.ps1` 已有的純 PowerShell `Test`／`Assert`／fake adapter 架構；不引入 Pester 依賴。建議新增 `tests/RestoreSummary.Tests.ps1`，或在既有檔案追加獨立區塊。測試 Summary 時直接建立 `New-Run`、`New-RestoreItem` 的 fixture；以 PowerShell output redirection 捕獲 Host/Warning stream，驗證文字及警告數量。

| ID | 場景 | 最低驗證 |
| --- | --- | --- |
| S01 | 18/18 全部 `Verified` | `Complete`；Total 18、Not verified 0；無 Unverified 區段及 Warning |
| S02 | 15/18 混合狀態 | `Partial`；所有原始 Group、Tab、Path、ReasonCode 均正確 |
| S03 | `Verified=0`、`Total>0` | `Partial`，不得宣稱成功 |
| S04 | 空 `Run.Items` | `Empty`；0/0；無 Retry 指令 |
| S05 | `State=Aborted`，混合狀態 | `Interrupted`；包含未嘗試項目；例外原樣傳遞 |
| S06 | `Aborted` 但 Item 均為 `Verified` | 不輸出整次 run 成功的結論 |
| S07 | `OutcomeUnknown` | 警告用 `not verified`，不寫 `failed`，不自動補做 |
| S08 | `NotAttempted`、`PreconditionFailed`、`SkippedInvalidPath` | 全部計入 Not verified，ReasonCode 有值才輸出 |
| S09 | 相同路徑跨 Group／同 Group 重複 | 逐項保留原索引，不去重 |
| S10 | Group/Item 原索引不連續 | 仍按原數字排序，不改成 1、2、3 |
| S11 | 含空白、單引號的 ReportPath | PreviewRetry 範例可直接用 PowerShell 安全引用 |
| S12 | 無 ReasonCode、未知 Status、空欄位 | 不拋出格式化例外；未知狀態計入未驗證 |
| S13 | Path 含換行／控制字元 | 顯示時跳脫，不新增偽造的 Console 行 |
| S14 | Retry child run 僅選了 2 項 | Summary Total=2；ReportPath 為 child 路徑 |
| S15 | 原本 `Complete-Run` 完整流程 | checkpoint 順序、Report JSON hash/schema、Invoke/Navigate 次數不變 |
| S16 | 最終 checkpoint 失敗 | 原 warning、JSON fallback、throw 仍存在；不宣稱 Report 已同步 |
| S17 | `WarningPreference='Stop'` | 顯示 warning 不會掩蓋原始 Restore 結果或例外 |
| S18 | `Show-RetryPreview` 既有整合測試 | 預覽、指紋及 Retry 安全限制維持原樣 |

補充：
- 確認在 PowerShell 7 執行既有與新增測試；在公司政策允許的前提下，另外驗證 Windows PowerShell 5.1。不可為測試繞過機器的 Execution Policy。
- 捕獲輸出時分開檢查 Information/Host 與 Warning stream；避免只斷言 `Write-Host` 的畫面效果。
- 既有 `ISSUE2-VALIDATION.md` 記錄的是候選版的 39 項離線測試，新增測試後應更新**實際執行的數據**，不能先填預期的通過數字。
- 這些測試不會驗證 Explorer 視窗可見性；該 regression 的 Live acceptance 仍是獨立事項。

## 8. 施工順序與檔案清單

1. **建立基準**：檢查 `git status --short`、既有 `Write-RunSummary`、`Complete-Run`、`Read-RunReport`、`Show-RetryPreview` 和測試；保存測試基線，不能覆蓋使用者未提交的改動。
2. **純邏輯**：在 `resume-explorer.core.ps1` 新增 `Get-RunSummary`；完成狀態推導、固定／未知 Status 統計、Group/Item 排序及零項目處理。
3. **呈現層**：擴充 `Write-RunSummary`，保留 `Report: ... (<State>)` 舊格式，新增結果摘要、逐項路徑和 WARNING，產生正確 quoting 的 PreviewRetry 指令。
4. **例外／持久化檢查**：確認 `Complete-Run` 的 `finally` 和 checkpoint 失敗情境仍按原路徑運作；只有經測試證實必要，才加最小的 checkpoint freshness 提示。
5. **自動化測試**：新增 S01–S18，執行現有 `tests/Issue2.Tests.ps1` 與新增測試；不使用真實 Explorer 進行測試。
6. **文件更新**：`README.md` 新增成功、部分未驗證、中止示例與 Retry 注意事項；`ISSUE2-VALIDATION.md` 更新實際測試結果；`Backlog.md` 增加／標記這個小型 enhancement（不得誤將 Issue-2 核心修復標記完成）。
7. **審閱差異**：`git diff --check`、`git diff`；確認沒有更動 Restore／Retry 核心、安全機制或 Schema；不要自動 commit 或發布。

| 檔案 | 預期變更 |
| --- | --- |
| `resume-explorer.core.ps1` | 新增 `Get-RunSummary`；擴充 `Write-RunSummary`；必要時最小化處理 checkpoint freshness |
| `resume-explorer.ps1` | 預期 **不變** |
| `tests/RestoreSummary.Tests.ps1` 或既有 `Issue2.Tests.ps1` | 新增純資料與整合測試 |
| `README.md` | 說明輸出與 Warning／Retry 用法 |
| `ISSUE2-VALIDATION.md` | 記錄真正執行的驗證結果 |
| `Backlog.md` | 記錄 feature/task 狀態，不變更原 Issue-2 驗收條件 |
| `resume-explorer-Issue-2-fix-plan.md` | 原 Issue-2 核心設計文件原則上保持不變 |

## 9. 完成定義（Acceptance Criteria）

- [ ] A01：任意非 Verified 項目都能直接從 Console 找到**原 Group / ItemIndex / RequestedPath / Status / ReasonCode（有值時）**，且未嘗試項目沒有被漏掉。
- [ ] A02：`Total = Verified + Not verified`；Status 小計與所有 Run.Items 一致；排序穩定、重複路徑不合併。
- [ ] A03：全部 Verified 不產生未驗證 Warning；部分未驗證必須明確 Warning；Aborted 不被呈現成成功；空 run 不被誤判為 Complete。
- [ ] A04：`Report: <full path> (<State>)` 保持可辨識，指向真正的當次 JSON；沒有第二個 log。
- [ ] A05：提示的 `PreviewRetry` 指令可以安全引用含空白／單引號的路徑；不自動執行 PreviewRetry 或 Retry。
- [ ] A06：`Completed`、`Aborted`、Exit/Error 行為、checkpoint 與既有 Report Schema 不變。
- [ ] A07：Restore 建立／導覽次數、順序、timeout、candidate selection 及 Retry 安全檢查完全不變；沒有新增 Explorer side effects。
- [ ] A08：所有新增離線測試與原先回歸測試通過；Windows PowerShell 5.1 若政策阻擋，應如實註記未驗證。
- [ ] A09：`README.md`、Backlog 與驗證文件一致；不將候選版或可見性問題宣稱已驗收。
- [ ] A10：`git diff` 僅含本次核准的摘要、測試及文件變更；由維護者決定 commit 和 release。

## 10. 風險、回滾與後續

| 風險 | 控制方式 |
| --- | --- |
| 將 `OutcomeUnknown` 說成失敗而造成重複建立 | 全程採用 `not verified` 語意，不觸發任何自動補做 |
| 報告過長／含私有路徑 | 只列非 Verified 項目；使用原索引，不新增網路傳輸；提示使用者妥善保管 Console 和 JSON |
| Console 輸出變更影響外部文字 parser | 保留原 `Report: <path> (<State>)` 第一行及 CLI 參數；機器整合應讀既有 Schema 1 JSON |
| Warning 在 `finally` 意外變成 terminating error | 採 native Warning stream 並顯式 `-WarningAction Continue`；以 S17 驗證 |
| 最終寫檔失敗但仍顯示 Report path | 保留既有 checkpoint failed 訊息與 throw；不得聲稱 Report 已更新 |
| 誤把此 enhancement 當成 Issue-2 完整解決 | 不碰 Explorer 可見性、Group identity 或原 Horizon VDI live acceptance |

**回滾**：僅還原新增的 summary 邏輯、輸出及對應文件／測試；因不更改 Schema、Snapshot、Retry 格式或 Restore 演算法，不需資料遷移。既有 `Report: ... (<State>)` 行與原始 `Write-RunSummary` 仍可恢復。

**最終建議**：優先實作「純結果計算 + Console 報告 + 離線驗證」，先不引入 log 子系統、GUI、Summary 模式開關或自動 Retry。這能快速改善可診斷性，同時將 Issue-2 核心風險和本次輸出 enhancement 清楚隔離。
