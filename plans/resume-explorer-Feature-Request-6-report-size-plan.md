# Feature Request-6 — Error-aware / Run-family-aware JSON Report Retention：同步清理詳細計畫

- 初稿：2026-11-01；本次決策更新：2026-11-02
- 優先級：**P2**（若證實儲存耗盡或 checkpoint 效能嚴重退化，再依證據升級）
- 狀態：**Reviewed / Proposed；本次只有文件規劃，尚未實作 Retention／清理**
- 主要決策：**優先保存有價值的異常紀錄**，以完整 **Root Run Family** 為單位；**同步／機會式清理（Synchronous, post-run cleanup）**，不使用 Task Scheduler、背景排程、服務或常駐程序
- 分工：[FR-9 診斷等級](resume-explorer-Feature-Request-9-diagnostic-level-plan.md) 負責未來 Compact／Full；**本 FR 只決定 Report 保留與容量證據，不要求改變診斷 Schema**
- 原始真實 Report 可能包含個人／公司路徑，**不得加入公開 repo**；量測結果只放去識別化摘要

## Implementation Order & Dependency Gate（2026-11-02 決策）

**優先實作建議：Task-3 Single-Instance CLI Guard，然後才允許 FR-6 的實際清理功能上線。** 這是 **FR-6 工作流內的相對優先序**，並不覆蓋全專案已存在的 P1 Issue-4／Task-1 或提高本 FR 的 P2 優先級。

**Task-3 詳細設計／測試計畫：** [`resume-explorer-Task-3-single-instance-cli-guard-plan.md`](resume-explorer-Task-3-single-instance-cli-guard-plan.md)（2026-11-02 Reviewed / Proposed；**尚未實作**）。本 FR §5.2／Phase 2A 保留依賴與 Cleanup 整合界線；實作／驗收 Global CLI Guard 的詳細依據以 Task-3 獨立計畫為準。

| 工作線／順序 | 工作項目 | 先決條件 | 可獨立交付／驗收 |
| --- | --- | --- | --- |
| **優先獨立實作（Track A）** | **Task-3：整個 CLI 的跨 Shell Single-Instance Guard**（本計畫 Phase 2A） | **不依賴 FR-6 Phase 0–2**、無需修改 Report Schema，也不依賴 Issue-6 | 兩個不同 Shell／Process 同時執行時，只有一個 Action 可以進入；第二個 fail fast、無副作用；正常與異常退出後能再次取得鎖 |
| **可先做／平行（Track B）** | **FR-6 Phase 0 → 1 → 2**：唯讀容量量測 → Family graph／分類 → Review/Pin／DryRun | Phase 1 需 Phase 0 基線／fixtures；Phase 2 需可靠分類；**不需要 Task-3** | 完全不刪檔的容量基線、A/B/C/Unknown 分類與 deterministic DryRun |
| **兩條線合流後** | **FR-6 Phase 3：顯式 Opt-in Family Cleanup** | **Task-3 驗收通過 AND Phase 0–2 驗收通過 AND 跨檔刪除／中斷恢復安全 Gate 通過** | 在受控範圍中可安全清理完整 Family；任何疑點 fail-closed |
| **最後** | **FR-6 Phase 4：Restore／Retry 結束後的同步 Cleanup** | **Phase 3 已通過驗收**，以及確認 final checkpoint／summary／Retry family lock／Single-Instance lock 順序 | 本次命令內有界清理、維護失敗不改 Restore／Retry 結果；不使用 Scheduler 或背景程序 |

```text
Track A: Task-3 single-instance (可先實作) ---------+
                                                  +--> FR-6 Phase 3: Safe Cleanup --> Phase 4: Post-run Sync
Track B: FR-6 Phase 0 --> Phase 1 --> Phase 2 -----+
                       + Phase 3 的跨檔 crash-recovery safety gate
```

**Dependency 分界**：
- **Issue-6 ≠ Feature Request-6**：Issue-6 為 Google DriveFS Shell Hang 的歷史已緩解事件（已歸檔在 `plans/DONE`），**不是 Task-3 或 FR-6 的前置條件**。
- **FR-9 Compact/Full 不阻塞 FR-6**：FR-6 的 Family 分類與保留不能依賴診斷詳細程度，繼續以當前 V1 Full Report 量測和設計；若 FR-9 另行改 Schema，才安排相容性回歸。
- **Task-3 是 Phase 3/4 的必要前置，不是 Phase 0–2 的前置**：原 Phase 2A 只是分段編號，**不代表必須等 Phase 2 結束才能做 Task-3**。
- **嚴格安全 Gate**：若 Phase 3 的完整 Family 刪除無法安全處理 crash／部分檔案遺失，仍可保留 Task-3、Phase 0–2 的獨立成果；不得因已有鎖就認定 Cleanup 可上線。

## 1. 決策摘要與範圍

使用者確認的初始 Retention Policy：

| Tier | 分類 | 目標保留 | 安全規則 |
| --- | --- | --- | --- |
| A | **未解決／未確認／需調查的異常 Family** | **全部保留**（不受 5 個配額限制） | 預設保護，**不自動刪除**；無法判定時也歸 A |
| B | **曾有異常，但已由使用者明確確認處理完畢的 Family** | **最近 5 個完整 Families** | 超額部分僅在安全預檢與使用者授權後成為清理候選 |
| C | **全程成功、沒有已知異常的 Family** | **最近 1 個完整 Family** | 用於正常行為／效能 Baseline；先考慮保留期再清理其他成功紀錄 |

**5 + 1 是對「可輪替」的 Tier B/C 計數，並非全域硬上限**。Pinned、進行中、資料損壞、來源不明、需要調查的 Tier A Family 可以使實際總數超過 6。若磁碟仍持續成長，**告警與顯示容量，不得偷偷丟失安全證據**。

本 FR 不處理 Snapshot 的定時保留（FR-3／FR-8）、Explorer Process／Hang（Issue-5／Issue-6）、同步 COM/UIA 超時根因（Issue-4）；也不修改 Restore／Retry 的 Invoke／Navigate 或原子 checkpoint 流程。

**量測先行仍然有效**：若實際磁碟負擔很小，Phase 0/1 可僅交付分類、DryRun 與觀察結果，**不強行推出刪檔功能**。若之後完成安全清理能力，**目標整合方式**是在一次成功完成的 Restore／Retry 命令尾端、且所有必要的 checkpoint 已持久化及相關 Retry lock 已釋放後，**於相同程序同步檢查並執行有界維護**，然後才返回 CLI。此為 post-run maintenance，**不是排程**；清理必須通過獨立安全與效能驗收，初版不得默默啟用刪除。

**術語區分**：「同步」是**與這次 Restore／Retry 同一個呼叫流程、並於回傳前完成或跳過維護**，不表示「每次必定刪除」或「清理一定有嚴格 wall-clock deadline」。它也不等於 Run 的同步 checkpoint：**清理不得介入單次 Restore／Retry 的任何副作用前 checkpoint**。

## 2. 現況與證據（直接對照現有程式碼）

截至 2026-11-02：

- `resume-explorer.core.ps1` 的 `New-Run` 建立 `SchemaVersion=1`；`Read-RunReport` 目前只接受 V1；`resume-explorer.ps1` **沒有** `-DiagnosticLevel`，也沒有清理 Report 的 Action。雖然先前 `5afd928` 的 commit 題目寫了 `feat`，其實際 Git diff **只有 Markdown**，不能因此視 FR-9 或本 FR 已實作。
- 預設 Root 報告儲存於 `%LOCALAPPDATA%\ResumeExplorer\Runs\<RunId>.json`；`Initialize-RunPath` 先 `CreateNew` 預留路徑，然後原子 checkpoint。自訂 `-ReportPath` 可指向其他位置。
- Retry 子報告位於**來源報告旁**的 `RetryRuns\<ChildRunId>.json`，可因多次 Retry 出現巢狀 `RetryRuns`；每個子 Run 含 `ParentRunId`／`RootRunId`／`RootReportPath`。
- `Get-RetryDescendantItems` 由 Root 路徑的 `RetryRuns` **遞迴掃描所有 JSON**，再按 family 選出子項目。`Start-RetryRun` 使用 `<RootReportPath>.retry.lock` 排他鎖；`Show-RetryPreview` 會產生來源 Report 旁的 `.retry-preview.json`，但目前**不使用這個 family lock**。
- `Completed` **不等於**全部 `Verified`；`Get-RunSummary` 依每個 Item 的 `Status` 計算結果，沒有在 JSON 裡持久化「已處理／已確認」的 Retention 狀態。
- 舊案例的 V1 Full Report 為 **3,002,321 bytes**（18 Items、83 Samples、5,115 累積 Views）。記憶體中清空 `Samples.Views` 後重序列化約 **116,701 bytes**；僅 minify 約 **1,514,104 bytes**。已證實「重複記錄 Views」是**單份容量來源**，**尚未證實**它造成 Issue-4 Timeout，也未量測實際歷史總量。

**重要結論**：目前既無「異常已處理」欄位，也沒有可安全原子刪除整個 Family 的儲存佈局。**不可直接寫一個只看 Status 或保留最近五個 `*.json` 的刪檔迴圈**。同步時機本身不提供檔案交易原子性，也不會消除其他 CLI 程序、舊版本程序或既有 PreviewRetry／Retry 的競態。

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

**目前檔案分散在共享 Runs 目錄與遞迴 RetryRuns，沒有「單一目錄原子刪除整個 Family」的保證**。目前 `Retry` 只有 Family 排他鎖，`PreviewRetry`／`Restore` 並未取得全命令鎖。新計畫先增加**一個** CLI single-instance guard，從進入命令到 Cleanup 完成始終持有；如此同一使用者的新版本 CLI 不會同時執行 Retry 與 Cleanup。即使完成單例保護，**跨檔刪除失敗及舊版／外部讀寫者仍要獨立保護**，但不必預設設計大型 Lock Manager。

### 5.1 先比較三個替代方案

| 方案 | 優點 | 風險／決策 |
| --- | --- | --- |
| 每個 JSON 單獨輪替 | 最簡單 | **拒絕**：可能刪掉 Root 或 Verified Child，破壞 Retry 家族 |
| 直接依 5 個 Root Family 同步刪除 | 清理量容易理解 | **拒絕立即實作**：不能區分 A/B/C，且跨檔案刪除不具原子性 |
| **A/B/C 分類 + 預覽 + 有條件 Family 清理** | 符合診斷價值，允許保護異常及成功 Baseline | **採用作為設計方向**，但刪除需先證明排他性與 crash recovery；否則停留在 DryRun |

### 5.2 **Single-Instance Execution：任何時間僅允許一個 `resume-explorer` 命令**

**核心規格（建議獨立於 Retention 先實作）**：同一 Windows 使用者／機器中，透過新版 `resume-explorer.ps1` 啟動的命令（`Capture`、`Preview`、`Restore`、`PreviewRetry`、`Retry`，以及未來的 `Cleanup`）**一次只能有一個正在執行**。此規格包含正常 Restore／Retry 和尾端同步 Cleanup 的**整個命令生命週期**，不是「僅 Cleanup 互斥」。

**推薦最小實作：穩定位置的 OS 排他檔案鎖（`FileStream` + `FileShare.None`）**：

1. 在 CLI entry point、任何 action 可能列舉 Explorer／讀寫 Snapshot／Report **之前**，先取得固定的每使用者鎖，例如 `%LOCALAPPDATA%\ResumeExplorer\resume-explorer.instance.lock`（候選名稱）。它位於 **`Runs` 目錄外面**、由程式擁有，**永遠不參與 Report Retention／刪檔**；無論 `-ReportPath` 指向何處，使用相同 lock anchor。
2. 用 .NET `[IO.File]::Open(path, OpenOrCreate, ReadWrite, FileShare.None)` 取得排他開啟的 `FileStream`，**持有開啟的 handle 才是鎖**；檔案存在不代表仍有命令在執行。建立父目錄需受控／可重入，失敗時 **fail-closed**，不得略過鎖繼續 Restore。
3. 第二個 CLI 在 lock 被持有時**立即拒絕執行（fail fast）**，輸出可理解的「已有 resume-explorer 命令執行中；稍後重試」；**不排隊、不阻塞等待、不啟動背景 retry**。必須區分 sharing violation 與權限／磁碟錯誤，不應將所有 I/O 例外都誤報為「已有命令」。
4. 最外層 `try/finally` 包覆完整 action dispatch **及可選 post-run Cleanup**，最後才 `Dispose()` handle。正常結束、內部 `throw` 或 `Ctrl+C` 等可處理終止均應釋放；程序遭終止時 Windows 會關閉 handle。**不要用「偵測檔案是否存在」或「定期刪除過期 .lock」推定鎖狀態**。
5. `Start-RetryRun` 現有的 **family `.retry.lock` 保持不變**，先在其 `finally` 釋放；外層 instance lock 仍持有，接著同步 Cleanup，**Cleanup 完成／略過後**才釋放 instance lock。不要引入新的 Lock Manager、輪詢式工作佇列、背景 worker 或每個 Family 額外協調鎖來解決「本工具的新命令」互斥。
6. **範圍界線**：相同 Windows 使用者、共用相同 `LOCALAPPDATA`／鎖檔路徑的新版本 CLI 會互斥；不保證不同 Windows 帳號、不同機器、**舊版本腳本**、第三方工具或直接 dot-source core 函式也遵守本鎖。跨帳號共用的自訂 ReportPath **不納入自動清理**；遇到無法確認的舊版／外部讀寫者，跳過正式刪除，不能宣稱絕對全機單例。
7. **相容性**：以前可同時執行的 `Preview`／`Capture` 也會被拒絕，屬**有意的可觀察行為變更**。先測試並更新 README、版本、使用指引與必要 CLI 測試；保留既有 Action 名稱、參數、正常輸出、Report Schema、Retry 安全判斷。可考慮讓 FR-8 的自動 Capture 在 Busy 時安全跳過本輪，而不是等待或中斷前景 Restore。

**跨 Shell／跨 Process 保證（使用者確認的需求）**：

鎖的互斥由 **Windows 檔案分享／開啟規則**保證，與 PowerShell 變數、當前 Working Directory、Terminal Tab 或 Process 內部狀態無關。任何新版 `resume-explorer.ps1` 命令，只要使用**同一個本機檔案的完整路徑**且從 CLI 進入相同鎖流程，取得不到 `FileShare.None` 排他開啟就必須在 Action 前結束。

| 同時執行的環境 | 預期行為／驗收 |
| --- | --- |
| 兩個 `pwsh.exe`，各在獨立 Terminal／Tab | 第一個執行；第二個 **fail fast** |
| `powershell.exe` 5.1 與 `pwsh.exe` 7（如有安裝） | 同一鎖檔路徑時跨版本互斥 |
| VS Code Integrated Terminal 與 Windows Terminal／獨立 PowerShell | 不受 Terminal／Host 差異影響 |
| CMD 透過 `powershell.exe -File` 啟動 CLI，另一個 PowerShell 執行 CLI | 不受外層 Shell 影響 |
| 從不同 `$PWD`／不同 Git worktree 或複製的新版 CLI 啟動（共用同一鎖設定） | 鎖路徑與 Repository／Snapshot／ReportPath 無關，**仍須互斥** |
| 相同 Windows 帳號的不同登入／RDP Session | **只有兩邊實際解析到同一個可共用鎖檔、其檔案系統遵守 Windows sharing semantics 時**才保證；需隔離實測 |
| 不同 Windows 帳號、不同機器、舊版 CLI 或直接呼叫 core 函式 | **不在本功能的互斥保證範圍**；不得據此進行危險 Report 清理 |

鎖檔根目錄應由 Windows 使用者的 **LocalApplicationData 已知資料夾**取得並正規化為絕對路徑（`%LOCALAPPDATA%\ResumeExplorer\resume-explorer.instance.lock` 為可讀示例），而非依賴 `$PWD`、`$PSScriptRoot` 或 `-ReportPath`；需明確處理未設定、無權限、不可寫與路徑指向非預期位置時的 fail-closed 行為。**兩個 CLI 必須真正打開同一個檔案**，不能各自建立不同工作目錄下的同名鎖檔。

- **Lock lifetime**：取得鎖成功 → 整個 Action（包含任何長輪詢、finally、最終 checkpoint 和摘要）→ Retry family lock 已釋放 → opt-in 同步 Cleanup 完成／跳過 → **在外層 `finally` 關閉 FileStream**；不得在 `Complete-Run` 返回或輸出摘要後就提前釋放 instance lock。
- **Busy detection**：嘗試開啟失敗且確認是 sharing violation 時回報「另一個命令執行中」，並拒絕進入 Action；其他權限、檔案系統錯誤另行說明並 fail-closed。**鎖檔存在不代表被持有**；不要為了解除 Busy 刪掉或覆寫鎖檔。
- **Cancellation／Crash**：通常由 `finally` 釋放；程序被強制結束時依 Windows 檔案 handle 關閉機制解除鎖。此處僅處理互斥，不表示已完成 Report checkpoint 或多檔清理恢復。
- **Backward compatibility**：這是有意的行為改變：第二個 `Capture`／`Preview` 也會被拒絕。確認所有入口走到 guard，現有命令參數、既有單執行行為及輸出保持相容，README／版本與 tests 在實作時更新。

**替代方案評估**：Windows named `Mutex` 也能跨程序限制執行，但會增加命名／Session namespace／ACL／AbandonedMutex 處理；目前已使用 `FileShare.None` 實作 Retry 排他，因此**推薦共享固定 lock-file 技術，但不要重用可被刪除的 `<RootReportPath>.retry.lock` 作為全域單例鎖**。若不同 Windows sessions 必須互斥，先以相同使用者的 `LOCALAPPDATA` 穩定路徑驗證跨 Session 行為，而不是假設 `Local\` named mutex 能涵蓋全部 sessions。

**命令與鎖的生命週期（設計意圖，尚未實作）：**

```text
CLI 取得 single-instance lock（失敗則立即退出，不做副作用）
  → 執行 Capture / Preview / Restore / PreviewRetry / Retry / Cleanup
  → Restore/Retry 時：final checkpoint → summary → release family retry lock
  →（僅啟用時）同步清理符合保留條件的其他舊 Run Families
  → CLI finally: release single-instance lock → 返回使用者
```

**仍然必須處理的獨立風險（不應過度設計並行架構）**：

- **刪除前最小重驗**：檢查 candidate family closure／hash／metadata／Pinned／A-B-C 分類與受管路徑。發現未知子代／內容變動立即 skip；不因有單例鎖就跳過安全分類。
- **中途崩潰／跨檔刪除**：即使只有**一個**命令，多檔案刪到一半遇到斷電仍可留下殘缺 Family。Phase 3 必須提出**最小可驗證的 fail-closed／recoverable 方案**，不能破壞 Retry 對已 Verified／Attempted 子代的查核；若找不到簡潔安全的做法，只提供 DryRun 或手動管理，**不得冒險實作 Delete**。
- **外部／舊版程序**：Single-instance guard 對它們沒有強制力；採保守預設，尤其舊版可能不尊重新的刪除標記。不得在缺乏可驗證前置條件時清理仍可能由它們使用的 Family。
- **同一 CLI 同步清理**：只有本次命令的最後 checkpoint 已保存且原操作正常返回，才允許清理其他舊 Family；清理失敗只影響 Cleanup summary／warning，不能改變 Restore／Retry 的狀態、exit code 或副作用次數。

**Gate：**先以**兩個獨立 PowerShell process** 的離線測試驗證排他、fail-fast、正常與異常釋放、跨 PS5.1/7（如可用）、不同 `-Action`、無 COM/Explorer 副作用，以及 lock file 不被 Cleanup 選取。通過後，Single-instance 才可作為 FR-6 正式清理的併行保障；**不用實作另一套複雜的 Family Lock Manager**。

### 5.3 目標：Restore／Retry **同步、機會式（opportunistic）**清理

**明確排除**：Task Scheduler、Background Service、常駐程序、獨立 Timer、稍後自動重試，以及在使用者離開 CLI 後才清理。所謂「自動」只表示**使用者已啟用這項功能時，跟隨本次 Restore／Retry 命令尾端執行**；不是自動排程。

**建議執行順序（目前尚未實作）：**

1. **在 CLI 最外層先排他取得 single-instance lock，取得不到則立即拒絕第二個命令**。成功取得後才執行正常 `-Action Restore`／`-Action Retry`；不得在偵測候選、新建視窗、Invoke、Navigate、任何中間 checkpoint 或尚在建立 Retry 子報告時清理。
2. `Complete-Run` 先完成**最後一筆原子 checkpoint**，原本的 `Write-RunSummary` 照舊輸出。若 Restore／Retry 發生例外（包括最後 checkpoint 失敗），**維持原始例外與 exit behavior，直接略過 Cleanup**；切勿在 `catch`／`finally` 裡對未知狀態動手。
3. `Start-RetryRun` 返回之前會在自己的 `finally` 釋放既有 Root family `.retry.lock`；**此時外層 single-instance lock 仍被同一 CLI 持有**，不會有第二個新版命令插入。Cleanup hook 應位於 CLI／外層流程、且在 `Start-RetryRun` 完整返回之後；不可直接加進 `Complete-Run`。
4. 正常返回後，**再次唯讀核對**本次 report 已存在、可解析、最終 `State=Completed` 且 checkpoint 可讀；即使包含 `OutcomeUnknown`／`NotAttempted`，也只是表示本次流程已結束，**該 Family 仍屬 A 且受到保護**，不能從 Restore `Completed` 推論可以刪除。現有 `Start-RestoreRun`／`Start-RetryRun` **沒有向 CLI 回傳結構化 RunId／ReportPath 結果**；若整合點需要識別本次 Family，應以**內部明確的執行結果／上下文傳遞**（或等價方式）取得，保留現行 stdout、主控台 Summary 和公開參數相容性，**不可解析 `Write-Host "Report: ..."` 文字來決定刪除資格**。
5. 只有在功能已明確啟用、Report 屬受管預設 Runs 範圍、沒有競態／鎖風險、且發現超過 B/C soft retention 的**完整可驗證歷史 Family** 時，才嘗試清理其他**合資格的舊 Family**。本次新產生的 Family、Pinned、A／Unknown／Custom 一律不在候選中。
6. 對於資料不完整、Busy、超時軟預算、掃描失敗、尚無候選的情境，輸出簡短 `Skipped`／`Deferred` 原因，**立即返回**；不排入背景工作。下次使用者再次執行 Restore／Retry 時才可能重新檢查。
7. 清理結果**顯示在原 Restore／Retry summary 之後**，例如 `Cleanup: skipped (disabled/no candidates)`、`Cleanup: 1 family, N bytes`、`Cleanup warning: ...`；不得偽造 Verified 數量，也不輸出敏感 RequestedPath。**清理完成／跳過後，外層 `finally` 才釋放 single-instance lock，再返回 CLI**；即使命令失敗也必須釋放。

**觸發矩陣（最終期望行為）**：

| 命令／條件 | Post-run Cleanup | 原因 |
| --- | --- | --- |
| `Restore` 最後 checkpoint 成功、命令正常返回 | **Eligible to check**（不是必刪） | 不干擾主流程；當次可能是 Partial，但受影響 Family 繼續保護 |
| `Retry` 最後 checkpoint 成功、函式正常返回，Root family lock 已釋放 | **Eligible to check** | 不造成自己持有鎖又嘗試清理的問題 |
| `Restore`／`Retry` 例外、`Aborted`、最終 checkpoint 寫入失敗／不可信 | **Skip**，保留原失敗 | 不在不確定狀態下清理，也不掩蓋原例外 |
| `Capture`／`Preview`／`PreviewRetry` | **Skip** | 維持現有操作語意，尤其 PreviewRetry 目前未統一持有 family lock |
| 使用 `-ReportPath` 指向非受管預設目錄、或來源 Family 位置不可信 | **Skip** | 避免在自訂報告操作時意外清理另一個目錄 |
| 同一使用者的第二個新版 CLI 在第一個仍執行時啟動 | **整個第二個命令 fail fast**（尚未進入任何 Action） | single-instance lock 覆蓋全部命令與同步清理，無等待／無佇列；舊版／外部操作不在此保證範圍 |
| 使用者明確執行未來的 `-Action Cleanup` | 依 `DryRun`／明確確認模式執行 | 手動入口，**不屬排程** |

**Backward compatibility**：既有 CLI 目前既沒有 single-instance gate，也沒有 retention 動作。**所有 Action 一次只能有一個執行**屬新增的明確行為（第二個命令會 fail fast）；在實作時必須同步更新 README、版本／測試與使用提示。Cleanup 的第一個可用版本**預設不刪**，以 explicit opt-in 啟用（候選 `-CleanupAfterRun`；手動 `-Action Cleanup -DryRun`）。只有獨立離線測試與安全驗收後，才考慮日常預設同步清理及 opt-out；不可偷偷改掉既有 Restore／Retry 的結果。

### 5.4 有界同步維護、錯誤隔離與協調協定（實作前須決策）

**效率／回傳延遲**：

- **快速 No-op**：先以便宜且安全的條件判定是否需要進一步掃描；沒有可安全確認的候選就跳過。**不能只掃描部分目錄就宣稱 Family 完整可刪**。
- **有界工作量**：候選初始值可考慮「每次最多清理 1 個完整 Family、約 2 秒 soft budget」，但**必須先量測**，不是硬性驗收數字。限制候選數、檔案 I/O、掃描範圍、一次的清理嘗試量；剩餘合資格 Family 留到**下一次使用者主動呼叫**處理，不開背景佇列。
- **軟時間限制不是同步 I/O 的硬中斷保證**：單次 PowerShell/.NET 檔案 I/O 或網路磁碟可能阻塞超出預算；不得強殺執行緒，也不能超時後讓未完成的清理繼續在背景跑。若無法保障正常使用的回應性，**只交付 DryRun 或僅手動 Cleanup**；以 P50/P95 增量延遲與長尾案例判定。
- **降低不必要的掃描**：可以在既有受管目錄使用低成本門檻／單次 Cleanup 計畫來避免每次全量解析；如使用 persisted last-scan metadata，必須可選、可重建、不能替代實際刪除前的完整 revalidation，不擴張成排程或複雜資料庫。
- **保留政策不變**：Tier A／Unknown 全保護；Tier B 最近 5、Tier C 最近 1（可搭配已驗收的 Grace period），Pin 及本次新 Run 保護優先。單次清理預算可能讓合資格舊 Family 暫時超額，這是預期行為而不是錯誤。

**並行與儲存安全（以 Single-instance 為主、最小必要防護）**：

- **不設獨立 Cleanup Lock Manager**：整個 CLI 的 OS 排他 handle 持續涵蓋 `Restore`／`Retry` 及 post-run Cleanup；所有新版命令（包含 `PreviewRetry`／手動 `Cleanup`）**同時只會執行一個**。第二個命令取得不到 instance lock 就 fail fast；不要在 Cleanup 裡再設等待式 per-family queue／worker。既有 `<RootReportPath>.retry.lock` 仍保留，以維持 Retry 原有保障與相容性。
- **新舊版界線與保守跳過**：舊版 CLI、其他 Windows 使用者／外部工具沒有義務取得新鎖，不能聲稱 single-instance 已保護它們。清理前仍需確認完整 family graph、hash、review metadata、目錄歸屬及 Sidecars；遇到任何不明的更新、活躍外部讀寫證據或資料無法驗證時，**跳過本次 Family**，不冒險刪除。此限制應在首次啟用 Cleanup 前清楚告知。
- **跨檔失敗仍需最小恢復方案**：即使單一命令執行，刪除 Root＋Child／Sidecars 時突然斷電仍不是原子動作。先提出最小的 recoverable/fail-closed 保護（例如獨立且持久化的 retire/tombstone 狀態，配合 Retry 的拒絕與恢復驗證；是否需要由測試決定），不得為了簡化而留下可能被誤判為可重試的殘缺 Family。**找不到可驗證且成本合理的方案，就停在 DryRun／手動檔案管理，而不是引入大型交易框架或盲目刪檔**。

**結果與失敗隔離**：

- **Restore/Retry correctness、報告 checksum 與 exit code 優先**。清理失敗不得更改剛保存的 Run、Status、ReasonCode 或退出結果；原本成功仍是成功、原本失敗仍傳回原例外。僅就 Maintenance 顯示獨立 Warning／Skipped reason，不能輸出 `Report saved` 之類未經驗證的成功訊息。
- 如使用 `Write-Warning`，須考慮 `$WarningPreference='Stop'` 或呼叫端的 WarningAction 可能令警告變成 terminating exception；設計上應明確讓 cleanup warning **不會覆蓋主操作結果**，又不能悄悄吞掉維護問題。保留單獨可檢查的 Cleanup 結果，避免誤判已刪。
- **例外不做補刪、不得重試 Restore**：清理失敗只能在下一次正常 CLI 執行再評估；不可增加額外 Invoke／Navigate、改變 Checkpoint 順序或因清理錯誤導致已成功的 Restore 被重送。
- DryRun 與正式 Cleanup 均需要可驗證、去識別化的統計（`FamiliesExamined`、`ProtectedA`、`RetainedB`、`RetainedC`、`Eligible`、`Deleted`、`FreedBytes`、`DeferredReason`），不能提供敏感 Path；真正刪除後才報 freed bytes。

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

### Phase 2A — Single-instance 執行保護（Task-3：建議優先獨立實作，不必等待 Phase 0–2）

1. 先寫**不接觸 Explorer** 的兩個 PowerShell process 排他測試，涵蓋所有 `-Action`、新舊 `powershell.exe`／`pwsh.exe`（如環境支援）、第二個命令 fail fast、無等待及錯誤訊息；使用隔離的測試 lock path，**不得在測試時佔用使用者的真實 instance lock**。
2. 在 `resume-explorer.ps1` 最外層加一個共享所有 Action 的 `FileShare.None` guard（helper 可小型化、與 Report Retention 邏輯分離），並以 `try/finally` 保證釋放。鎖檔位於 `Runs` 之外，永久不列入清理；測試檔案存在但 handle 已釋放時**可以重新取得**。
3. Regression：驗證 lock 已持有時 `Capture`／`Preview`／`Restore`／`PreviewRetry`／`Retry` 不進入任何 Action；第一個命令正常、拋例外、Ctrl+C／程序被終止後，第二個命令能在 OS 釋放 handle 後繼續；針對不可建立鎖與權限失敗應 fail-closed。保留現有 CLI 合法輸出、Report Schema、既有 Retry family lock 與測試行為。
4. **Gate**：已證明同一 Windows 使用者的新版本 CLI 一次只執行一個；第二個命令不造成 Explorer 或 Report 副作用；不同使用者／舊版不在此保證範圍，使用者文件清楚告知。**此階段不實作任何刪除**。

### Phase 3 — 顯式 Family 清理（**有條件：Task-3 + Phase 0–2 + 跨檔恢復安全 Gate 均通過**）

1. 依靠已驗證的**單一 CLI 執行鎖**防止新版本的 Restore／Retry 與 Cleanup 同時進行；**不建立額外 Lock Manager**。另外驗證 Family 成員與 hash／metadata、受管路徑，對舊版／外部修改採保守跳過。
2. 單獨評估「多個 Root／Child JSON 清理到一半失敗」的最小 fail-closed／recoverable 設計；若無法確保殘留 Report 不會錯誤允許 Retry，**拒絕本 Phase**，保留 DryRun。
3. 實作有限範圍、顯式授權的手動 Cleanup；保留可核對的結果與 audit，發現任何資料差異直接 skip，不推測或繼續刪。驗證 B 最新 5、C 最新 1 的 soft target，永不清理 A／Unknown／Pin、本次新 Run、自訂 ReportPath 或 Snapshot。
4. **Gate**：獨立測試 single-instance 排他、未知／舊版存取、子代變更、磁碟／權限／鎖、crash-recovery 與現有 PreviewRetry／Retry safety 全部通過；禁止在日常 Explorer/VDI 直接測試真實刪檔。

### Phase 4 — **Restore／Retry 後同步整合**（必須先完成並驗收 Phase 3；取代自動排程）

1. **整合點**：在外層 `resume-explorer.ps1` 呼叫 `Start-RestoreRun`／`Start-RetryRun` 正常返回後，才進入可選的同步 Cleanup；**不置於 `Complete-Run` 的 `finally`**，避免最後 checkpoint 失敗仍清理、或 Retry family lock 尚未釋放。實作時需要**內部可取得的 RunId／ReportPath context**，不得以正規表示式讀取主控台 Summary，亦不得改變對外 Pipeline 輸出或造成額外的 `Write-Host`。此整合點僅是建議，先寫呼叫順序與輸出相容測試。
2. **條件式啟用**：先新增明確 opt-in 的 post-run maintenance（CLI 名稱待定），並保留獨立手動 `Cleanup`／`DryRun` 入口；後續如要預設啟用，必須另完成相容性與可停用設計的發布審核，不視為無影響變更。
3. **安全範圍與觸發**：只有受管報告、最後 checkpoint 成功、主命令無例外、家族鎖已釋放，且**原本在 CLI 起始時取得的同一把 single-instance lock 仍持有**時才檢查；**不取得第二把新維護鎖**。`Completed + OutcomeUnknown` 只允許**清理其他合格的舊 Family**，不能將目前這個 A 類 Family 刪除。
4. **快速返回**：無候選、只有 A／Unknown、尚未超額、不可取得鎖、權限不足或超出**軟**時間／候選預算即跳過；單次最多處理少數完整 Families（初始 1 個為候選）並在目前 CLI 中完成，不新增 Timer、Task Scheduler、背景 job 或待辦佇列。
5. **錯誤隔離**：正常 Restore／Retry 的報告與 exit code 不得因 Cleanup 失敗改變；清理失敗只記錄獨立 warning／結果與待處理數量，嚴格避免 `$WarningPreference='Stop'` 等影響主流程。不得自動重新執行 Restore／Retry 或遮蔽原始 exception。
6. **驗收 Gate**：測試「取得全命令鎖 → 正常 Restore/Retry → summary 已列印 → Retry family lock 已釋放 → 同步清理檢查 → 釋放全命令鎖 → CLI 返回」順序；第二個命令要 fail fast，不可插入執行。另測未掃描完成、磁碟錯誤、超額 Families、軟預算超時及 PowerShell WarningPreferences；若效能或安全成本不合理，僅保留已驗證的**手動 Cleanup** 能力，不推出預設 post-run 刪除。

**決策：不採用自動排程清理，也不把清理工作丟給背景程序。** 即使未來 FR-8 實作定時 Snapshot Capture，FR-6 的 Report Cleanup 仍只在使用者主動觸發的 CLI 中同步發生。

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
| 在第一個 CLI 中，`Start-RetryRun` 仍持有 family lock；另一 CLI 試圖 `PreviewRetry` | 同一 CLI 必須先完成 Retry、釋放 family lock 才可清理；第二個 CLI 因全命令鎖立即拒絕，不能插入 |
| 刪到一半停電、磁碟滿、I/O denied、部分 Sidecar | 若有 Cleanup，須證明一致性與 recovery；否則不得推出刪檔能力 |
| Root/Child schema V1；未來 V2 若由 FR-9 實作 | V1 原始契約不變，未知版本保護；V2 明確支援後才可納入清理 |
| 兩個 `pwsh.exe`／獨立 Terminal Tabs；不同 `$PWD` | 相同 per-user 絕對 lock-file 路徑，第二個立即拒絕，不進入任何 Action |
| Windows PowerShell 5.1 與 PowerShell 7；VS Code Terminal／CMD→PowerShell | **跨 Shell／跨版本／跨 Host** 排他成立，並確認鎖不依賴工作目錄或 CLI 檔案位置 |
| 第一個命令執行到 post-run Cleanup，第二個命令同時啟動 | Cleanup 全程仍持有 instance lock；第二個在原始 Action 之前 fail fast |
| 鎖檔存在但前一程序已退出或已釋放 handle | 新命令可重新取得；**不刪除鎖檔**才能恢復 |
| 同使用者不同 RDP Sessions／不共享相同本機鎖路徑／跨 Windows 帳號 | 同 Session／帳號／路徑的聲明要與測試一致；不同路徑或不同帳號**不能宣稱互斥** |
| Lock 檔案 ACL／disk 問題、sharing violation、意外終止 | 明確區分 Busy 與其他 fail-closed 錯誤；無副作用、沒有無限等待、OS handle 釋放後可重試 |
| 未啟用 Cleanup 的正常 Restore／Retry；其他 `Capture`／`Preview`／`PreviewRetry` | 與現有行為一致：不清理、不改 Report、無額外建立／導覽副作用 |
| 主流程正常結束、最後 checkpoint 可讀，且候選舊 Family 超額 | 僅在 Summary 與相關 Retry lock 釋放後，於**同一 CLI**檢查受管 Family 並同步清理少量合資格舊 Family |
| `Completed` 但 Partial／OutcomeUnknown／NotAttempted | 可檢查其他舊 Family；**本次 Partial Family 保護**，不把 Completed 當 All Verified |
| 主流程 `Aborted`、最後 checkpoint 失敗、尚未完整返回 | **不觸發 Cleanup**、保留原 Exception／exit code、沒有任何清理副作用 |
| 第二個新版 CLI 嘗試 `Capture`／`Preview`／`Restore`／`PreviewRetry`／`Retry`／`Cleanup` | 在 Action 前因 single-instance guard fail fast；**不等待且不修改任何 Explorer／Report／Snapshot** |
| 真實 instance lock 檔案持續存在但 handle 已釋放；程序 crash／Ctrl+C | 下次可取得新鎖，不以檔案存在與否判斷 Busy；lock anchor 位於 `Runs` 外，永不刪除；受管資料受 fail-closed 保護 |
| 清理 eligible Families > 每次候選／時間預算，或沒有候選 | 單次有界處理、其餘 `Deferred`；下一次使用者操作再處理，**無背景 job／Timer／Scheduler** |
| 清理失敗、locked、I/O denied、`$WarningPreference='Stop'`、子樹變動 | 只回報維護 Warning／Skipped，**主 Restore／Retry 既有結果與退出碼不變**，不重送 Invoke／Navigate |
| 使用自訂 `-ReportPath`、未來手動 `-Action Cleanup` | 自訂路徑不觸發 managed auto-clean；手動入口需明確授權／DryRun，所有路徑範圍與家族保護不變 |
| 同步清理延遲及完成率 | 離線假時鐘、不同家庭規模和實機 sandbox 量測增量 P50/P95、worst-case／slow IO 與 FreedBytes；若不符合回應性需求，保留手動模式而非做背景清理 |
| 既有 `tests/Issue2.Tests.ps1`／`tests/RestoreSummary.Tests.ps1` | 現有身份／single Invoke／Navigate／atomic checkpoint／Retry／輸出驗證不退化 |

**既有測試完整性**：不要為了「測試通過」改掉現有斷言。若真要修改測試，先定位根因，保留或補充等價的安全回歸測試。先前文件曾記錄 Issue2 39 PASS、RestoreSummary S16 斷言失敗，這是**歷史基線**，本次文件更新不宣稱已解決該測試。

## 8. 驗收準則與明確不做事項

- **分類正確性**：可以完整且無歧義地區分 ProtectedUnresolved、ReviewedAnomaly、CleanSuccess、UnknownProtected；所有可疑資料預設保留。
- **Retention policy**：僅 B 最新 5、C 最新 1 可輪替，A／Unknown／Pin 不限量；數量／Grace 是保留策略，**不是自動刪除授權**。
- **安全性**：不能刪掉 Root 但留下可由 Retry 操作的子 Run，也不能把原本已 Verify/Attempt 的證據清走導致重送；不得清理自訂 ReportPath、Snapshot、受管範圍外檔案或未知 Sidecars。
- **可觀測性**：DryRun 顯示保護原因、候選、節省 bytes、異常數及實際超額，而非僅一句「刪除 N 個 JSON」。
- **量測**：有客觀磁碟和執行期成本數據；不把節省磁碟空間視為 Issue-4 Timeout 已解決。
- **安全交付**：Phase 0–2 可獨立結案為調查／Read-only capability；Phase 3 只有刪除協定通過 Gate 才允許手動清理；Phase 4 在其上進行**同步 post-run 整合**。若有任何安全或效能風險，**不推出自動清理**。沒有預設刪除、定時排程、背景 job 或改 Report Schema。
- **同步整合正確性與 Single-instance**：正式啟用後同一 Windows 使用者的新版本 CLI **一次只允許一個 Action**，整個命令期間持有固定 OS 排他 lock（包含 Cleanup）；第二個命令立即拒絕、不排隊。只有主命令正常返回且最終 checkpoint 成功、Retry family lock 釋放後才進行清理；Cleanup 沒有背景生命周期、排程或額外 Invoke／Navigate，主流程的 Status／ReasonCode／exit code／Summary 保持一致。
- **可預期的回傳成本**：只作有界且可跳過的同步清理；量測每次 CLI 增量 P50/P95、slow I/O 長尾及 Scan/Deleted/FreedBytes。單次 I/O 不受 Stopwatch 硬中斷，**不得聲稱嚴格 wall-clock 保證**；若造成不可接受的延遲，保留手動 Cleanup 而不預設整合。
- **失敗與隔離**：Try-lock 失敗、無候選、超出軟預算及 cleanup error 可以顯示 Deferred／Warning，但不改原 Restore／Retry 的 exception/exit code，不得刪除 A／Unknown／Pin 或跳過 revalidation。
- **發布前**：若未來實作 Cleanup，更新 README、Backlog、CLI 用法、啟用／停用策略、測試與版本資訊；**首次只 opt-in**，後續如改成預設同步清理必須先明確評估向後相容性並告知使用者。離線回歸後再在**隔離的可重設環境**驗證。絕不在日常 Explorer/VDI 用大規模 Restore、強制結束 Explorer 或真實 Report 刪除做壓測。

## 9. 建議工作單元（依相對優先序與依賴整理）

**Track A：優先獨立交付 Task-3；Track B 可在 Track A 之前或同時進行，但兩條工作線都通過驗收後才能清理。** 以下編號只是建議推進順序，不表示只能嚴格依序執行，也不改變其他 P1 問題的全專案優先級。

1. **Track A / 下一個建議實作** — `feat(task3): single-instance CLI guard`：最先可獨立交付，一次一個命令、跨 Shell fail-fast、全命令 `try/finally` 與雙 Process 離線回歸；**不依賴 FR-6 Phase 0–2**，仍保持既有 Retry family lock。
2. **Track B / 可先或並行** — `investigate(fr6): measure report inventory and costs`：Phase 0 唯讀統計容量／checkpoint 成本、收集去識別化基線；**不依賴 Task-3**。
3. **Track B** — `test(fr6): add synthetic family classification fixtures`：Phase 1，建立 Root/Child graph、未知資料 fail-closed 與 deterministic tests，勿削弱既有測試。
4. **Track B** — `feat(fr6): read-only family inventory and dry run`：Phase 1–2，只提供分類／容量／候選預覽，不刪檔；後續補最小 Review/Pin metadata，確保 A→B 必須人工確認。
5. **合流／必要安全 Gate** — `design(fr6): prove minimal fail-closed family cleanup`：**前提：Task-3 + Phase 0–2 均通過驗收**；再證明完整 Family 清理與多檔中斷恢復，不合理則保留 DryRun。
6. **合流／有條件交付** — `feat(fr6): opt-in family cleanup`：Phase 3，只有 Gate 通過才交付顯式安全刪除，並做故障注入與 Retry lineage 回歸測試。
7. **最後整合** — `feat(fr6): opt-in synchronous post-run cleanup`：Phase 4，**依賴 Phase 3**，只在 `Restore`／`Retry` 正常返回並釋放 Retry family lock 後清理；instance lock 覆蓋整個命令，不使用 Scheduler／背景 job。
8. **文件維護（隨交付更新）** — `docs(fr6): keep Backlog/plan/README/version/tests in sync`：本次只更新規劃；實作時記錄有意的第二命令 fail-fast 相容性變更及每階段驗收，**除非明確要求，保留 Git Working Tree、不建立 Commit**。

**與 FR-9 的關係**：FR-9 仍追求日常 Compact／調查 Full，但不應讓「保留哪個 Family」取決於診斷詳細程度；不論 V1 Full 或未來 V2 Compact，保留分類均以**安全的 Run/Item 狀態與完整 lineage**為準。

**歷史決策**：從「直接縮小 JSON」轉成「量測先行、優先保存高價值錯誤報告」，再把「最近 3–5 個一般 Family」改為 **A 全保護／B 最近 5／C 最近 1**。先取消「定時自動清理」，改採 Restore／Retry 後同步機會式清理。**2026-11-02 本次修訂：以全 CLI 單一執行檔案鎖取代過度複雜的 Cleanup 並行鎖規劃，明確限定一次一個 `resume-explorer` 命令、第二個 fail fast，保留最小的跨檔中斷／外部修改防護**。此政策目前只在文件中，**不代表單例鎖或清理功能已實作**。
