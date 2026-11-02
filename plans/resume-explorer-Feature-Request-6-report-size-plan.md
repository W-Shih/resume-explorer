# Feature Request-6 — Error-aware / Run-family-aware JSON Report Retention：詳細調查與實作計畫

- 初稿：2026-11-01；本次決策更新：2026-11-02
- 優先級：**P2**（若證實儲存耗盡或 checkpoint 效能嚴重退化，再依證據升級）
- 狀態：**Reviewed / Proposed；本次只有文件規劃，尚未實作 Retention／清理**
- 主要決策：**優先保存有價值的異常紀錄**，同時留下少量正常 Baseline；以完整 **Root Run Family** 為單位，而不是以單個 JSON 或單純時間排序清理
- 分工：[FR-9 診斷等級](resume-explorer-Feature-Request-9-diagnostic-level-plan.md) 負責未來 Compact／Full；**本 FR 只決定 Report 保留與容量證據，不要求改變診斷 Schema**
- 原始真實 Report 可能包含個人／公司路徑，**不得加入公開 repo**；量測結果只放去識別化摘要

## 1. 決策摘要與範圍

使用者確認的初始 Retention Policy：

| Tier | 分類 | 目標保留 | 安全規則 |
| --- | --- | --- | --- |
| A | **未解決／未確認／需調查的異常 Family** | **全部保留**（不受 5 個配額限制） | 預設保護，**不自動刪除**；無法判定時也歸 A |
| B | **曾有異常，但已由使用者明確確認處理完畢的 Family** | **最近 5 個完整 Families** | 超額部分僅在安全預檢與使用者授權後成為清理候選 |
| C | **全程成功、沒有已知異常的 Family** | **最近 1 個完整 Family** | 用於正常行為／效能 Baseline；先考慮保留期再清理其他成功紀錄 |

**5 + 1 是對「可輪替」的 Tier B/C 計數，並非全域硬上限**。Pinned、進行中、資料損壞、來源不明、需要調查的 Tier A Family 可以使實際總數超過 6。若磁碟仍持續成長，**告警與顯示容量，不得偷偷丟失安全證據**。

本 FR 不處理 Snapshot 的定時保留（FR-3／FR-8）、Explorer Process／Hang（Issue-5／Issue-6）、同步 COM/UIA 超時根因（Issue-4）；也不修改 Restore／Retry 的 Invoke／Navigate 或原子 checkpoint 流程。

**量測先行仍然有效**：若實際磁碟負擔很小，Phase 0/1 可僅交付分類、DryRun 與觀察結果，**不強行推出自動清理**。自動套用 Retention 是後續有條件功能，而不是這份計畫的既定承諾。

## 2. 現況與證據（直接對照現有程式碼）

截至 2026-11-02：

- `resume-explorer.core.ps1` 的 `New-Run` 建立 `SchemaVersion=1`；`Read-RunReport` 目前只接受 V1；`resume-explorer.ps1` **沒有** `-DiagnosticLevel`，也沒有清理 Report 的 Action。雖然先前 `5afd928` 的 commit 題目寫了 `feat`，其實際 Git diff **只有 Markdown**，不能因此視 FR-9 或本 FR 已實作。
- 預設 Root 報告儲存於 `%LOCALAPPDATA%\ResumeExplorer\Runs\<RunId>.json`；`Initialize-RunPath` 先 `CreateNew` 預留路徑，然後原子 checkpoint。自訂 `-ReportPath` 可指向其他位置。
- Retry 子報告位於**來源報告旁**的 `RetryRuns\<ChildRunId>.json`，可因多次 Retry 出現巢狀 `RetryRuns`；每個子 Run 含 `ParentRunId`／`RootRunId`／`RootReportPath`。
- `Get-RetryDescendantItems` 由 Root 路徑的 `RetryRuns` **遞迴掃描所有 JSON**，再按 family 選出子項目。`Start-RetryRun` 使用 `<RootReportPath>.retry.lock` 排他鎖；`Show-RetryPreview` 會產生來源 Report 旁的 `.retry-preview.json`，但目前**不使用這個 family lock**。
- `Completed` **不等於**全部 `Verified`；`Get-RunSummary` 依每個 Item 的 `Status` 計算結果，沒有在 JSON 裡持久化「已處理／已確認」的 Retention 狀態。
- 舊案例的 V1 Full Report 為 **3,002,321 bytes**（18 Items、83 Samples、5,115 累積 Views）。記憶體中清空 `Samples.Views` 後重序列化約 **116,701 bytes**；僅 minify 約 **1,514,104 bytes**。已證實「重複記錄 Views」是**單份容量來源**，**尚未證實**它造成 Issue-4 Timeout，也未量測實際歷史總量。

**重要結論**：目前既無「異常已處理」欄位，也沒有可安全原子刪除整個 Family 的儲存佈局。**不可直接寫一個只看 Status 或保留最近五個 `*.json` 的刪檔迴圈**。

## 3. 定義：哪些 Family 有錯、哪些算已處理？

### 3.1 Family 身分與完整性

- **Root Family** = 唯一的 Root Run Report + 所有具合法父子鏈的 Retry 後代 Report + 與這些 Report 對應的 preview sidecars、family lock／必要 retention metadata。它是**一個計數單位**，即使包含數十個 JSON。
- 以 `RunId`／`ParentRunId`／`RootRunId`、Root 的**實際受管路徑**與父子鏈共同驗證。不能只以目錄、相同 `RequestedPath` 或 `RootRunId` 字串就認為可信，尤其不能把其他 Family 的 `RetryRuns` 一起清掉。
- 本期只在工具明確管理的預設 Runs 目錄中建立清單。**`-ReportPath` 自訂位置、外部副本、Snapshot／使用者自行移動的 Report，一律不納入自動清理**。不信任 JSON 內的 `RootReportPath` 作為刪除指令；它僅作 lineage **驗證資訊**。
- Root／Child 缺檔、重複 RunId、斷鏈、環狀 ParentRunId、版本不支援、非預期 reparse point／symlink／junction、無法解碼、無法驗證的時間戳或 metadata、讀取失敗，都分類為 **UnknownProtected**，不得猜測其為正常成功。

### 3.2 分類規則（保守且可測試）

| 事件／紀錄 | 分類 | 原因 |
| --- | --- | --- |
| Root 與所有可驗證後代均 `Completed`，每個非空 Run 的 Items 全為 `Verified`，沒有 Run／Item Error 或已知異常 | **C: CleanSuccess** | 可做 Baseline；最終仍可能有 Explorer 可見性 false positive，故保留最新一份及適當寬限期 |
| 任一 Run 為 `Running`、`Aborted`、未知 State、缺漏 JSON／欄位或有 Run／Item Error | **A: ProtectedUnresolved / UnknownProtected** | 完成狀態不可靠，錯誤證據需保存 |
| 任一 Item 是 `OutcomeUnknown`、`PreconditionFailed`、`NotAttempted`、`SkippedInvalidPath` 或未知 Status | **A: ProtectedUnresolved** | 不可因整個 Run 顯示 Completed 就當成成功 |
| Root 曾 `OutcomeUnknown`，後代 Retry 為 `Verified`，**尚無人工確認** | **A: ProtectedUnresolved** | Retry 成功不是對原始不確定副作用的追溯證明 |
| 曾有非成功的 Run／Item，且使用者**明確標記已處理**，完整 family 未再變更 | **B: ReviewedAnomaly** | 屬可輪替的歷史異常家族；仍按 5 個保留 |
| `Completed` 但 Items 為空、attempt flags／狀態不一致、同一 Item 重複索引 | **A: UnknownProtected** | `Empty` 不等同已驗證成功；不可信資料不能進清理佇列 |
| `Verified` 但有可恢復的 `TransientReadErrorCount` 等警告 | **依風險分類／供使用者 Pin** | 不把所有 transient warning 都自動認定為失敗；在 DryRun 顯示 warning 摘要，由測試決定是否需升為 A |

- **不要僅因 Attempted flag 為 `true` 就當成失敗**：正常完成的 `Verified` 項目也可能曾經正當執行 Invoke／Navigate。
- 分類以**整個 Family 的歷史最嚴重結果**為準；子報告成功**不能**抹除 Root 的歷史異常。
- `Get-RunSummary` 的 `Verification` 是衍生顯示值，不是持久化的「已解決」證明。
- 明確區分 **UserReviewed／ResolvedForRetention** 與 **RuntimeVerified**：前者只影響清理資格，**絕不**改變 Retry eligibility、安全狀態或既有 JSON。

### 3.3 如何把 A 轉為 B（必須另設明確 Review Gate）

目前沒有能證明「異常已處理」的欄位，因此**不能自行將任何有錯的 Family 從 A 轉為 B**。實作時應提供簡單的人工確認（例：標記 Root Run 已檢查、已手動處理或已決定不再 Retry），不得根據子 Run Verified 自動轉換。

- 建議將 `Pinned`／`ReviewedResolved` 等**最少量的 Retention 狀態存於 JSON Report 之外**，以免修改原報告造成 `PreviewRetry` 的 SHA-256 hash guard 失效。
- 獨立狀態需綁定 Root `RunId`、受管 canonical path、Root/Child family fingerprint 或等價的版本資訊；**若產生新 Child、內容／家族結構變更，原有 Review 自動失效並回到 A**。
- Metadata 缺失／損壞／權限不足不應默認為 Reviewed 或清理許可；**fail-closed**。Pin 優先於任何輪替上限。
- Review 不表示系統保證最初的副作用不存在；確認對話／CLI 必須告知刪掉 Family 之後將失去相應 Retry／RCA 證據。這是**文件與未來實作設計**，不是現有功能。

## 4. 排序、輪替與安全邊界

1. **先劃出受管集合**：只列舉明確管理的預設 Runs 範圍；用 full path normalization、大小寫／分隔符邊界檢查及 reparse point 檢查排除逃逸。不要直接信任檔案名稱、`RootReportPath` 或使用者提供的任意遞迴路徑。
2. **建立 family graph**：讀取 Root、在共享／巢狀 `RetryRuns` 中尋找後代，交叉核對每一個 Child 的 Parent、Root、真實位置與 metadata；無法確認閉包完整性或存在孤兒時，保護受影響 Family／檔案。
3. **先套用不可刪條件**：Pin、A、UnknownProtected、活躍 Restore／PreviewRetry／Retry、鎖爭用、尚在產生、缺漏／損壞、custom path、無法辨識的 sidecar 等，**優先於容量與數量配額**。
4. **計數依 Root Run 家族**：分別將已審核的 B 依可信 `Root.StartedAtUtc`（或經驗證的等價時間）保留最近 5 個，將 C 保留最近 1 個；同時使用 Root `RunId` 決定性排序平手。時間無法驗證則保護而不是靠 last-write-time 猜測。
5. **Grace period（候選，需驗收）**：考慮至少 7 天的成功 Report 寬限期，避免剛完成就因下一次 Restore 被刪而無法調查 false-positive；此時 C 暫時可能多於 1 個。明確以**軟額度**呈現，而非違反需求。
6. **只建議、不得偷刪**：首版輸出 `Keep / Protected / ReviewRequired / EligibleForCleanup`、原因、bytes、RootRunId 短標識、各種計數與預估節省；不顯示敏感 RequestedPath。沒有掃描完成、明確使用者授權及安全 Gate 時，任何候選都不可刪。
7. **不可保證固定磁碟上限**：例如有 30 個尚未處理的 `OutcomeUnknown` 時全部仍需保護；顯示「超過容量建議／待處理異常」，而不是清除最老的 A。
8. **不混淆 Snapshot Retention**：FR-3／FR-8 的 Snapshot 歷史和本 FR 的 Report Run Family 應使用獨立選項、保護規則及刪除範圍。

## 5. 工作階段與安全清理：先設 Gate，不能直接實作 `Remove-Item`

**目前檔案分散在共享 Runs 目錄與遞迴 RetryRuns，沒有「單一目錄原子刪除整個 Family」的保證**。`Retry` 使用排他 family lock，但 `PreviewRetry` 不保證取得相同鎖，Restore 起始的 root checkpoint 也不是與 Retention 共用的全程鎖。僅依當下 `State=Completed` 或檔案 `.retry.lock` 是否存在不能排除競態。

### 5.1 先比較三個替代方案

| 方案 | 優點 | 風險／決策 |
| --- | --- | --- |
| 每個 JSON 單獨輪替 | 最簡單 | **拒絕**：可能刪掉 Root 或 Verified Child，破壞 Retry 家族 |
| 直接依 5 個 Root Family 同步刪除 | 清理量容易理解 | **拒絕立即實作**：不能區分 A/B/C，且跨檔案刪除不具原子性 |
| **A/B/C 分類 + 預覽 + 有條件 Family 清理** | 符合診斷價值，允許保護異常及成功 Baseline | **採用作為設計方向**，但刪除需先證明排他性與 crash recovery；否則停留在 DryRun |

### 5.2 清理功能必要前置條件（未通過即不實作自動清理）

- **同一 Family 的 Restore/PreviewRetry/Retry/清理協調**：評估統一的生命週期鎖／交易守門方式；任何調整都必須測試不影響既有 CLI 與 Retry lock 保障。特別驗證「使用者剛 Preview，另一程序準備 Retry」的時序。
- **Revalidate-before-delete**：以掃描時產生的 candidate manifest／hash、完整 family 成員列表／狀態／Pinned metadata／目錄身份，在真正清理前**重新掃描驗證**；有新 Child、檔案變動、異常或鎖爭用就整個 Family 跳過。
- **多檔失敗一致性**：先設計可恢復的保守清理交易（如受控保留區＋manifest／recovery log），並證明對 crash、拒絕存取、磁碟不足、部分刪除、重啟後的恢復正確。**不能假設搬移共享 Root/Child 檔案或跨檔刪除是原子操作；搬移也會影響 `RootReportPath` 及 Retry**。
- **只處理可確認的完整閉合 Family**：任何未知 Child、Sidecar、外部依賴、檔案 reparse point／hard-link 風險等，在沒有可靠支援前都**跳過**。不能刪除共享 `RetryRuns` 目錄、其他 Family 的 Preview／Lock 或使用者自訂 ReportPath。
- **安全中斷**：清理過程失敗，不得默默留下會被當成合法可重試的殘缺 Family；如不能提供安全恢復機制，**退回只提供預覽／人工決策，不實作刪除**。
- **明確啟用**：初版僅 DryRun，後續即使有實作 Cleanup 也應 `WhatIf`／`Confirm` 或等價顯式 opt-in，不能在一般 `Restore`／`Retry` 完成時默默執行。自動定時清理另開驗收 Gate。

## 6. 分階段執行計畫（沒有一階段預設應修改正式程式碼）

### Phase 0 — 既有行為、基準與完整資料盤點（Read-only）

1. 核對 Git、`AGENTS.md`、`Backlog.md`、`README.md`、Restore/Retry 實作與測試，建立來源版本基準。
2. 安全唯讀列舉**受管** Runs 的總 Report 數量、完整 Family 數、各類 A/B/C/Unknown 候選、Root/Child 比例、bytes、保留後預估 bytes、孤兒、Sidecars、無法辨識的資料。不讀取／列印多餘的使用者目錄細節到報告。
3. 量測單次 Report 的 checkpoint serialize/write、總寫入與記憶體（以去識別化離線 fixture）；確認歷史磁碟問題與執行期效能成本應由不同功能處理。
4. 建立 synthetic family fixtures，涵蓋 Root→Child→Grandchild、不同 Root 共享 `RetryRuns`、重複 Path、`OutcomeUnknown`→Child Verified、資料損壞與未知版本。
5. **Gate**：所有分析均不更動真實 Report／Snapshot；若尚無可靠 family graph 或 disk 基線，停止在調查，不開始清理功能。

### Phase 1 — 純函式 Family Enumerator + Classifier（無刪檔能力）

1. 設計純函式把已解析的最小報告資訊轉換成 Family Graph、分類及 `ProtectedReason`，與 Shell COM／UIA 完全解耦。
2. 建立可信 Root/Child membership、缺漏／型別不可信欄位的 fail-closed 規則；不以 `Get-RunSummary` 的文字輸出判定清理資格。
3. 不修改現有 `Read-RunReport` 的 Retry 語意；若需要嚴格驗證，優先做**專屬唯讀 Retention reader**，避免為了新功能破壞歷史 V1 Retry。
4. 先新增獨立離線測試，未通過前不做任何刪除。**Gate**：所有 anomalous/unknown 情況都能正確保護。

### Phase 2 — Review/Pin 記錄 + Retention DryRun（無刪檔能力）

1. 定義最小的外部 Review／Pin metadata（與報告 hash／family 版本綁定），不重寫原 JSON；提供可撤銷的明確人工確認，且新增 Child 後使已審核狀態失效。
2. 僅產生可核對的計畫：每個 Family 的 Tier、根 ID、Root/Child 數、總 bytes、應保留原因、預期會被清理的路徑清單（**僅顯示相對識別符／不暴露敏感路徑**）、預估節省及仍保留的 A／Unknown 數。
3. 在不同 Report 狀態、缺漏 metadata、數量邊界（0／1／5／6／100）、時間相同、跨時區、Grace period、Pin／Unpin 下驗證排序與保護邏輯。
4. **Gate**：DryRun 多次執行結果決定性、沒有對檔案的副作用，且能清楚說明「為什麼這個 Family 被保留／候選清理」。

### Phase 3 — 顯式 Family 清理（**有條件，需專門安全審核**）

1. 先提出並驗證 family-wide 並行存取協定、預覽與實際清理間 TOCTOU 防護、部分刪除／中斷恢復機制；如無法滿足，**拒絕本 Phase**。
2. 實作有限範圍、顯式授權的 cleanup；保留完整 audit 與可核對的結果。發現差異只跳過，不重新猜測清理候選。
3. 驗證 5+1 的 soft limit，不能覆蓋 A/Unknown/Pin；不可改動 Report JSON、既有 PreviewRetry／Retry 結果或 Snapshot。
4. **Gate**：離線故障注入、同 Family 併發 Preview／Retry、子代新建、磁碟／鎖／權限與 crash-recovery 測試全部通過，才評估推出。

### Phase 4 — 自動排程（**可選，非本需求預設交付**）

只有長期實測確有必要、Phase 3 稳定且經明確批准時，才考慮排程；預設關閉，提供停用／調整與 DryRun 日誌，保留無法確定的資料。不要與 FR-8 自動 Capture 排程隱含綁定。

## 7. 測試矩陣（以離線 Deterministic Tests 為主）

| 測試案例 | 必須成立 |
| --- | --- |
| 完全成功的單 Root，已存在 1／2／10 個成功 Families | 僅最近 1 個進一般輪替保留，其餘若過 Grace 且合資格才候選清理 |
| Root 13 Verified／1 OutcomeUnknown／4 NotAttempted | **A Protected**，即使 `State=Completed` 也不會清理 |
| Root OutcomeUnknown → 子 Retry Verified | 未人工 Review 前仍 A；原 Root 不被改寫 |
| Root `Aborted` 但 Items 全 Verified | A，不因項目全部 Verified 就當 C |
| `SkippedInvalidPath`／`PreconditionFailed`／`NotAttempted` | A，除非整個 family 經明確人工確認轉為 B |
| 已 Review 的歷史異常有 0／1／5／6 個 | 保留最近 5；超額僅產生候選，不動受保護者 |
| 成功但 Diagnostic transient error | 不因偶發可恢復錯誤默默把分類變成失敗；警告可供 Review／Pin |
| 空 Run、Running、缺漏 attempt flags／不合理 Status 或 Error | A/UnknownProtected，**fail-closed** |
| 多個 Root 共用巢狀 `RetryRuns`／交錯 Child | 只歸屬正確 Family，不誤刪另一 Root 的 Child |
| 重複 RunId、孤兒、斷鏈、環狀 parent、RootPath 不符、未知 Schema | UnknownProtected，掃描仍安全 |
| 自訂 ReportPath、外部路徑、junction／symlink、錯誤權限 | 不進自動清理集合，不越界 |
| Pin/Unpin、Review resolved、Review metadata 損壞、新 Retry Child | Pin 勝過配額；資料變動後 Review 失效並重新保護 |
| Preview 後報告被改寫或新增 Child | 清理前 hash/manifest 重新驗證失敗，整個 Family 跳過 |
| 活躍 Retry family lock／PreviewRetry 競態／Report 正在 checkpoint | 不對活躍或不確定 Family 清理 |
| 刪到一半停電、磁碟滿、I/O denied、部分 Sidecar | 若有 Cleanup，須證明一致性與 recovery；否則不得推出刪檔能力 |
| Root/Child schema V1；未來 V2 若由 FR-9 實作 | V1 原始契約不變，未知版本保護；V2 明確支援後才可納入清理 |
| 既有 `tests/Issue2.Tests.ps1`／`tests/RestoreSummary.Tests.ps1` | 現有身份／single Invoke／Navigate／atomic checkpoint／Retry／輸出驗證不退化 |

**既有測試完整性**：不要為了「測試通過」改掉現有斷言。若真要修改測試，先定位根因，保留或補充等價的安全回歸測試。先前文件曾記錄 Issue2 39 PASS、RestoreSummary S16 斷言失敗，這是**歷史基線**，本次文件更新不宣稱已解決該測試。

## 8. 驗收準則與明確不做事項

- **分類正確性**：可以完整且無歧義地區分 ProtectedUnresolved、ReviewedAnomaly、CleanSuccess、UnknownProtected；所有可疑資料預設保留。
- **Retention policy**：僅 B 最新 5、C 最新 1 可輪替，A／Unknown／Pin 不限量；數量／Grace 是保留策略，**不是自動刪除授權**。
- **安全性**：不能刪掉 Root 但留下可由 Retry 操作的子 Run，也不能把原本已 Verify/Attempt 的證據清走導致重送；不得清理自訂 ReportPath、Snapshot、受管範圍外檔案或未知 Sidecars。
- **可觀測性**：DryRun 顯示保護原因、候選、節省 bytes、異常數及實際超額，而非僅一句「刪除 N 個 JSON」。
- **量測**：有客觀磁碟和執行期成本數據；不把節省磁碟空間視為 Issue-4 Timeout 已解決。
- **安全交付**：Phase 0–2 可獨立結案為調查／Read-only capability；若刪除協定沒有通過 Gate，**不推出自動清理**。沒有默認清理或改 Report Schema。
- **發布前**：若未來實作 Cleanup，更新 README、Backlog、CLI 用法、測試與版本資訊；執行離線回歸後再在**隔離的可重設環境**驗證。絕不在日常 Explorer/VDI 用大規模 Restore、強制結束 Explorer 或真實 Report 刪除做壓測。

## 9. 建議工作單元與文件一致性

1. `docs(fr6): define error-aware family retention policy` — 本次計畫、Backlog、與 FR-9 邊界（**只改文件，不 Commit，除非使用者指定**）。
2. `test(fr6): add synthetic family classification fixtures` — 新增最小 schema/lineage/flags/State tests，既有測試不削弱。
3. `feat(fr6): add read-only report family inventory and dry run` — 先交付**沒有 Delete 權限**的列舉／判斷功能。
4. `feat(fr6): add explicit review and pin metadata` — 只有確認 A→B 與 metadata 變更可被安全驗證時才實作。
5. `design(fr6): prove safe family deletion and recovery` — 獨立安全審核 Gate；缺乏可行的無競態協定時**拒絕實作清理**。
6. `feat(fr6): opt-in family cleanup` — Gate 通過後選做，附故障注入與 recovery tests；自動排程另需明確核准。

**與 FR-9 的關係**：FR-9 仍追求日常 Compact／調查 Full，但不應讓「保留哪個 Family」取決於診斷詳細程度；不論 V1 Full 或未來 V2 Compact，保留分類均以**安全的 Run/Item 狀態與完整 lineage**為準。

**歷史決策**：從「直接縮小 JSON」轉成「量測先行、優先保存高價值錯誤報告」，本次再將「最近 3–5 個一般 Family」改為 **A 全保護／B 最近 5／C 最近 1**。此政策目前只在文件中，**不代表有清理功能上線**。
