# Task-4 — RestoreSummary S16 JSON 格式敏感斷言：RCA 與修復計畫

- **Review 日期：** 2026-11-02
- **優先級：** **P1（測試基線完整性）**；建議在 Task-3 Single-Instance CLI Guard 實作前以獨立變更處置
- **狀態：** **Completed / Test-only Fix Verified（2026-11-02）**；僅修改 S16 assertion 與相關文件，PS5.1／PS7 完整回歸通過，沒有 Production 變更
- **追蹤來源：** [Backlog.md — Task-4](../Backlog.md)
- **關聯：** [Task-3 Single-Instance Guard](resume-explorer-Task-3-single-instance-cli-guard-plan.md)、[Task-1 Automated Tests](resume-explorer-Task-1-automated-tests-plan.md)
- **範圍：** `tests/RestoreSummary.Tests.ps1` 中 S16 對 fallback JSON 的格式敏感 assertion；**不涉及真實 Explorer 的 Capture/Restore**

## 1. 結論（根因已驗證）

**S16 失敗的直接原因是測試把 `ConvertTo-Json` 的排版空白誤當成行為契約。** Windows PowerShell 5.1 目前在 pretty-printed JSON 的冒號後輸出兩個空格，S16 卻使用含一個空格的 `String.Contains`，所以即使有效 JSON 已輸出、原始 exception 及 warning 都正確，測試仍然失敗。

**建議：僅在已證明為錯誤假設的 S16 assertion 作最小修正，改為從 Information stream 擷取 fallback JSON、`ConvertFrom-Json` 解析後驗證語意。** **不要**修改 Production Code 的 JSON formatting 來配合該測試；保留原有例外、Warning、Report 路徑及禁止誤報儲存成功的驗證。

這是有證據支持的**測試缺陷**，不是為了「讓測試綠燈」而放寬對 Production 行為的約束。執行真正修復時仍須檢視每一項既有 assertion，確保保護力不變或更強。

## 2. Evidence：實際程式、重現與對照

### 2.1 Relevant Code

`tests/RestoreSummary.Tests.ps1` 中的 `S16 failed final checkpoint retains warning, memory JSON and original throw` 做了下列事情：

1. 建立只有一個 `NotAttempted` Item 的合成 Run，並建立原始 `[IO.IOException]`。
2. 將 `Invoke-RestoreGroups` 替身設為 no-op、`Write-RestoreCheckpoint` 替身設為 `throw $expected`。
3. 執行 `Complete-Run`，將 warning stream `3` 與 information stream `6` redirect 到 success stream，蒐集到 `$records`。
4. 驗證原始 Exception 參考相同；要求包含 `Checkpoint failed` 的 WarningRecord 恰好一筆。
5. 把 `$records` 全轉成文字，使用下列字串相符條件：

```powershell
Assert ($text.Contains('"SchemaVersion": 1') -and
        $text.Contains('Report: C:\runs\stale.json'))
```

最後還有斷言，避免不實的 `Report saved`／`Report updated` 文字。

`resume-explorer.core.ps1` 的 `Complete-Run()` 在 final checkpoint 失敗時，會寫入 checkpoint failure warning、以 `Write-Host (ConvertTo-Json -InputObject $Run -Depth 32)` 輸出記憶體 fallback，再 rethrow；外層 finally 仍輸出 Summary。Production 檔案 writer `Write-RestoreCheckpoint()` 同樣使用 `ConvertTo-Json`，但是 S16 的失敗發生在**Console fallback 文字斷言**，並非 JSON schema 或持久化失敗的證據。

### 2.2 可重現結果（2026-11-02，Dell G15，未操作 Explorer）

| 驗證 | 結果 |
| --- | --- |
| `powershell.exe` 5.1 `tests/Issue2.Tests.ps1` | **39/39 Passed**（前一輪 baseline） |
| `powershell.exe` 5.1 `tests/RestoreSummary.Tests.ps1` | **S01–S15 Passed，S16 Assertion Failed，S17 因前項中止未執行** |
| `pwsh.exe` 7 `tests/RestoreSummary.Tests.ps1` | **17/17 Passed，Exit Code 0** |
| 獨立 PowerShell 5.1 S16 受控診斷（未改測試檔） | Exception ReferenceEquals **True**；`Checkpoint failed` Warning **1**；fallback JSON InformationRecord **1** |
| 解析該 fallback JSON | `SchemaVersion = 1`、`Items.Count = 1`、`State = Completed`，解析成功 |
| JSON 文字精確字串比對 | `"SchemaVersion": 1` → **False**；`"SchemaVersion":  1` → **True** |
| 相同診斷中獨立 S17 原例外保護 | ReferenceEquals **True** |

**歷史證據界線：**上表是修復前的 RCA，當時尚無修正後完整 PS5.1 S01–S17 結果。修正後完整跨版本結果已於本文件第 9 節記錄，沒有以先前受控診斷取代完整測試。

### 2.3 Root Cause vs. Product Contract

- **Verified root cause：** S16 `Contains` 預期單一空格，但 `ConvertTo-Json` 的 pretty output 空格不是 JSON schema，也不是跨 PowerShell 版本的穩定契約。
- **Verified：** PS5.1 仍輸出可正確 `ConvertFrom-Json` 的 fallback；checkpoint 失敗仍 rethrow 原 `IOException`；warning 也存在。
- **Not established：** 沒有證據顯示實際磁碟 Checkpoint、Retry Safety 或其他 Production 邏輯被破壞；S16 的模擬錯誤不是實際資料遺失案例。
- **Scope boundary：** Console fallback 表示提供人／工具可讀的**記憶體狀態**；不能因 Report 路徑有顯示，就把未成功寫入的 Report 當成已完成持久化。

## 3. Alternative Fixes／取捨

| 方案 | 優點 | 評估 |
| --- | --- | --- |
| 改 Production `ConvertTo-Json` 排版、壓縮或手動替換空白 | 使原測試字串通過 | **不採用**：更動使用者可觀察輸出且掩蓋測試錯誤，增加相容性風險 |
| 測試使用 Regex `\s+` 匹配空白 | 小改動 | **次佳**：仍只檢查 JSON 文字片段，無法證明有效 JSON 或語意 |
| **測試解析 InformationRecord 的 fallback JSON** | 驗證合法 JSON、schema、run/item 內容，跨版本 | **採用**，在保留原有安全 assertions 的前提下最小替換 |
| 刪除／Skip S16 或放鬆 Exception／Warning assertion | 可以快速綠燈 | **禁止**：破壞原本的安全回歸保護 |
| 重構整個 Summary／Checkpoint 架構 | 可能改善設計 | **不採用**：缺乏 Production Bug 證據，超出本 Task |

## 4. 最小修復方案（已依此實作，結果見第 9 節）

### 4.1 修改範圍及保護契約

**預期唯一必要的 Production/Test 變更：** `tests/RestoreSummary.Tests.ps1` 中 S16 的 JSON 輸出比對片段。若發現需要調整其他 assertion，必須先有獨立 root cause 與明確理由；此方案預設**不修改** `resume-explorer.core.ps1`、CLI、JSON Schema 或正常輸出。

保留 S16 的既有斷言：

- `[object]::ReferenceEquals($caught, $expected)`：不可用同型別／相同訊息取代原例外 identity；
- `Checkpoint failed` 的 `WarningRecord` **恰好 1 筆**；
- Console Summary 仍包含所輸入 `Report: C:\runs\stale.json`；
- Console 不得誤輸出 `Report saved` 或 `Report updated`；
- 即使 checkpoint failed，記憶體 fallback 仍可讀，且不能假稱磁碟檔案已保存。

**只替換** `$text.Contains('"SchemaVersion": 1')` 這種和格式空白耦合的判定，並可增加更精確的正面斷言：必須有**一筆**可解析的 fallback JSON、`SchemaVersion = 1`、正確 `RunId`、`State`、`Items.Count` 及至少一個 Item 的 `GroupIndex`／`ItemIndex`／`Status`。如採完整 JSON roundtrip 斷言，也需避免比較無關的 pretty formatting 或時間戳格式細節。

### 4.2 安全的 Test Assertion 形狀（示意，非已改測試）

```powershell
# 保留目前 $caught / WarningRecord / 報告路徑 / 假成功文字等斷言。
$jsonRecords = @($records | Where-Object {
    $_ -is [Management.Automation.InformationRecord] -and
    $null -ne $_.MessageData -and
    $_.MessageData.ToString().TrimStart().StartsWith('{')
})
Assert ($jsonRecords.Count -eq 1) 'Expected one in-memory fallback JSON'
$memoryRun = $jsonRecords[0].MessageData.ToString() | ConvertFrom-Json -ErrorAction Stop
Assert ($memoryRun.SchemaVersion -eq 1)
Assert ($memoryRun.RunId -eq $run.RunId)
Assert ($memoryRun.State -eq $run.State)
Assert (@($memoryRun.Items).Count -eq @($run.Items).Count)
Assert ($memoryRun.Items[0].Status -eq 'NotAttempted')

# Existing checks remain: same original IOException object, exactly one
# checkpoint warning, Report path shown, no false "Report saved/updated".
```

**注意：**示意只描述局部修正，實作時應核對 `InformationRecord.MessageData` 在兩個 PowerShell 版本下的實際型別與擷取方式；如果有更可靠的 JSON record identity，可以用更精確的方式辨識，**不可**讓任何偶然的 JSON-like 文字通過。測試需在發生 fallback 缺失、invalid JSON、錯誤 schema 或錯誤 item 時明確失敗。

### 4.3 保持測試強度、不修改 Production 的理由

- 原始單空格 assertion 只證明格式存在特定子字串，**不證明 JSON 可解析**；改為嚴格解析並檢查關鍵欄位，可以提供更強的語意回歸保障。
- 例外 identity、warning count、summary path 與未宣稱儲存成功的檢查**完整保留**；不能以字串格式容忍作為理由刪除。
- 不需改 Report Schema、PowerShell CLI 參數、checkpoint 原子性、Restore／Retry 交易或版本號（若僅測試修正，按 Repository 版本政策決定是否更新）。

## 5. 驗證計畫／Regression Matrix

### 5.1 確定性測試（不碰 Explorer）

| ID | 測試情境 | Acceptance |
| --- | --- | --- |
| T4-01 | Windows PowerShell 5.1 執行 S16 | Fallback JSON 格式無關、可以解析，S16 通過 |
| T4-02 | PowerShell 7 執行 S16 | S16 仍通過，不因改測試引入 regression |
| T4-03 | S16 原始 Exception identity | `ReferenceEquals` 保持為 True；不可用同訊息的新 Exception 代替 |
| T4-04 | S16 final checkpoint failure | `Checkpoint failed` WarningRecord 恰好 1 筆 |
| T4-05 | S16 fallback JSON | 恰好一份可解析 JSON，SchemaVersion/RunId/State/Items 正確 |
| T4-06 | S16 JSON 缺失／非法／錯 Schema（負向邏輯） | Test 必須失敗，不能只因 Report 行文字存在而通過 |
| T4-07 | S16 Console Report path | 路徑仍出現在 Console，**不得宣稱磁碟寫入成功** |
| T4-08 | S16 未宣稱儲存成功 | `Report saved`／`Report updated` 仍不得出現 |
| T4-09 | S17 `$WarningPreference='Stop'` | 原始 Invoke Exception 不被 Summary Warning 覆蓋 |
| T4-10 | 全套 Restore Summary | PS5.1 與 PS7 都通過 S01–S17，沒有 Skip／0 tests |
| T4-11 | 原有 Issue-2 tests | 既有測試回歸不退化；兩版本如可用均實跑 |
| T4-12 | Production boundary | 不修改 `resume-explorer.core.ps1`、CLI、Report Schema，沒有真實 Shell COM/UIA／Explorer 操作 |

**變更驗證原則：**新斷言不只要在真實 fallback JSON 下通過，也要能在缺漏／無效 JSON 時失敗；只用 `ConvertFrom-Json` 不搭配 Schema/Items 等斷言仍不足。避免建立會依賴目前測試執行順序的隱性 Mock／全域狀態。

### 5.2 執行指令（實作修正後）

```powershell
# 在 Repository 根目錄執行；不啟動真實 Explorer
powershell.exe -NoProfile -NonInteractive -File .\tests\RestoreSummary.Tests.ps1
powershell.exe -NoProfile -NonInteractive -File .\tests\Issue2.Tests.ps1

# 若 PowerShell 7 已安裝
pwsh.exe -NoProfile -NonInteractive -File .\tests\RestoreSummary.Tests.ps1
pwsh.exe -NoProfile -NonInteractive -File .\tests\Issue2.Tests.ps1

git diff --check
git diff -- tests/RestoreSummary.Tests.ps1
```

- 每條測試命令記錄實際 `$LASTEXITCODE`、PowerShell 版本、passed count；**不得只看 Console 的最後一行**。
- 如果 Pester 5 不存在，不需為此次精簡修正安裝；目前測試是直接可執行的 PowerShell deterministic tests。
- 若 PS7／PS5.1 不可用，需記錄 `NotRun` 及理由，不得推定跨版本相容。
- 此任務不要求 GUI E2E，因 S16 使用 Mock 且不能接觸正式 Snapshot／Report／Explorer。
- 若執行後意外發現其他失敗，分開做 RCA；不要將失敗解釋為本項已修復。

## 6. 實作階段與交付

| Phase | 內容 | Exit Gate |
| --- | --- | --- |
| **0. RCA / Baseline — 已有證據** | 原檔維持不變，重現 PS5.1 S16 Fail、PS7 S16 Pass，獨立比對 JSON 原始空白與 Parsed Schema | **RCA Confirmed**（本文件第 2 節）；**不是 Fix Completed** |
| **1. Focused Test Correction** | 僅修正 S16 的格式敏感 JSON substring assertion，改為可解析的語意檢查；原始安全 assertions 保留 | 舊 Expectation 的錯誤性有記錄；No assertion weakening |
| **2. Cross-Version Regression** | PS5.1 + PS7 跑 S01–S17、Issue-2 tests；檢查失敗／負向情境 | 完整 Passing Evidence，無其他測試被修改來迎合 Production |
| **3. Documentation／Closeout** | 更新本計畫與 Backlog 的 Passed/Completed 狀態、結果、測試環境、實際 diff；同步 Task-3 baseline 註記 | Task-4 才可 Closed，Task-3 才能視 S16 Gate 解除 |

**優先序：**Task-4（P1，恢復可靠 baseline）→ Task-3（P2，CLI instance lock）。Task-4 僅是 Task-3 開發前的**測試環境品質 Gate**，不是 FR-6 Phase 0–2、Issue-4 或 Explorer Restore 行為的功能相依。

## 7. Definition of Done

- [x] 只修改經核實為錯誤假設的 S16 JSON 字串 assertion；任何既有測試變更都有明確 RCA，沒有刪除、Skip、放寬原始 Exception／Warning／Summary 安全檢查。
- [x] 在獨立 test fixture 中對合法 fallback JSON 成功解析，並驗證 SchemaVersion、RunId、State、Items/Status；無效／缺漏 fallback 會 fail。
- [x] PS5.1 完整 `tests/RestoreSummary.Tests.ps1`：**17/17 Passed、Exit Code 0**。
- [x] PS7 完整 `tests/RestoreSummary.Tests.ps1`：**17/17 Passed、Exit Code 0**。
- [x] `tests/Issue2.Tests.ps1` 在兩個 PowerShell 版本均 **39/39 Passed、Exit Code 0**。
- [x] 沒有變更 Production Checkpoint、Restore/Retry safety、Report Schema、CLI 或實際 Explorer 狀態。
- [x] 記錄新舊測試輸出、PowerShell 版本、修正前後根因證據與 Git Diff；檢查 `git diff --check`。
- [x] Backlog／Task-3 Plan 的 S16 狀態與實際結果一致；Task-4 已 Closed，Task-3 功能仍未實作。

## 8. Remaining Risks／重要限制

- **Fallback JSON 與持久化是兩回事：**S16 模擬 final checkpoint 失敗，檢查 Console 的記憶體狀態和錯誤傳遞，**無法證明真實磁碟 I/O／斷電後狀態**。現有原子 checkpoint 測試另由 Issue-2／未來整合測試提供。
- **跨版本差異可能不只空格：**JSON 出現 whitespace／indentation 差異本就合法；未來 formatter 變更時應靠解析後的 schema 語意驗證，而不是擴大特定 Regex 的容忍範圍。
- **不要誤判根因層級：**本次明確定位為 S16 斷言缺陷；不得據此宣稱所有 Summary、Checkpoint 或 Exception 過程都已實機驗證。
- **避免順手重構：**本次不建議改動 `Complete-Run()`、新增 Pester/Mock Framework、調整 `-WarningAction`、修改 Snapshot/Report Schema、調整 Restore 狀態定義或版本號。

## 9. 實作與結案證據（2026-11-02）

基準分支 `codex/fr6-retention-plan`，HEAD `5636864`，修改前工作樹乾淨。PS7 修復前 Summary 17/17、Issue2 39/39（均 Exit 0）；PS5.1 修復前 Summary S01–S15 PASS、S16 失敗（Exit 1），Issue2 39/39（Exit 0）。本輪重新重現了原始問題，未先改 assertions。

**實作範圍與理由：**僅調整 `tests/RestoreSummary.Tests.ps1` 的 S16 區塊，將單空格 substring 換成唯一 InformationRecord JSON 的嚴格解析；MessageData 使用 `.ToString()` 支援 Write-Host 的 HostInformationMessage／字串表示。檢查 SchemaVersion、原 RunId、State、Items 數量、首項 GroupIndex／ItemIndex／NotAttempted Status／RequestedPath。原 Exception ReferenceEquals、恰好一筆 checkpoint warning、原始 Report 路徑、禁止假成功文字的 assertions 均保留，其他 S01–S15／S17 及 Issue2 tests 不變。

S16 內的獨立負向 fixture 使用同一局部驗證 scriptblock，要求以下 **12 組**全部被拒絕：缺少 JSON、重複 JSON、非法 JSON、無關 `{}`、錯誤 SchemaVersion、RunId、State、Items 數量、GroupIndex、ItemIndex、Status、RequestedPath。沒有重跑 Complete-Run，沒有跨測試共享新增 Mock，沒有 Skip；Summary 測試總數仍是 17。

| 引擎 | 指令（均含 `-NoProfile -NonInteractive -File`） | 實際 PASS count | Exit Code |
| --- | --- | ---: | ---: |
| PowerShell 7.6.1 | `tests/RestoreSummary.Tests.ps1` | **17/17**，含 S16／S17 | **0** |
| PowerShell 7.6.1 | `tests/Issue2.Tests.ps1` | **39/39** | **0** |
| Windows PowerShell 5.1.22621.6931 | `tests/RestoreSummary.Tests.ps1` | **17/17**，含 S16／S17 | **0** |
| Windows PowerShell 5.1.22621.6931 | `tests/Issue2.Tests.ps1` | **39/39** | **0** |

每套均以獨立 native process 執行，逐筆計算 `PASS ` 行並核對 `$LASTEXITCODE`，不是只讀最後一行。PS5.1 在沙箱內顯示 Restricted、無法載入腳本；沙箱外可以讀到既有 CurrentUser **RemoteSigned**，故在沙箱外依原政策完成修復前／後回歸。沒有 `Set-ExecutionPolicy`、`-ExecutionPolicy Bypass` 或其他政策繞過。

**交付：**S16 測試與 Backlog／本計畫／Task-3 plan／`ISSUE2-VALIDATION.md` 狀態同步。Production core、CLI、Schema、Snapshot／正式 Report 和真實 Explorer 均未改動。沒有調整版本號或自動 Commit。Task-4 Closed；Task-3 的 S16 測試基線 Gate 解除，但 Task-3 的 Lock 與跨 Process 驗收仍 Pending，且不代表 Explorer E2E 通過。
