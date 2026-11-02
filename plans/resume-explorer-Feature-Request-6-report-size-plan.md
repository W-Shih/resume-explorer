# Feature Request-6 — JSON Report 精簡與有界診斷資料：Review／實作計畫

- 初稿：2026-11-01；本版 Review：2026-11-02
- 優先級：**P1**（`Backlog.md` Feature Request-6）
- 狀態：**Reviewed / Proposed；程式碼尚未修改，實作與驗收尚未完成**
- 範圍：減少 Report 診斷資料體積與 checkpoint 序列化成本，同時保留安全重試、問題診斷與舊報告讀取能力
- 原始案例：`02e5f26b61da4a1ba503bea37d15323f.json`，含真實使用者路徑，不得加入公開 repo

## 1. Review 結論及實測證據

**主因已定位為診斷 Sample 反覆複製全部全域 Explorer Views，而非單純 JSON 縮排。** 此結論指報告容量來源，**不是** Issue-4 `NavigationTimeout` 或 Explorer 卡頓的 RCA。

| 指標（同一份實際 Report） | 值／方法 |
| --- | --- |
| 原始檔案大小 | **3,002,321 bytes**（約 3.00 MB / 2.86 MiB） |
| Items / 狀態 | **18**；13 Verified、1 OutcomeUnknown、4 NotAttempted |
| Diagnostics.Samples | **83**（NewWindow 12、Baseline 24、BeforeInvoke 8、Detection 16、BeforeNavigate 8、Navigation 15） |
| Samples 裡累積的 Views | **5,115 筆**，非 unique Explorer View 數量 |
| 僅將原始物件以 `ConvertTo-Json -Depth 32 -Compress` 重序列化 | **1,514,104 bytes**（約縮小 49.6%） |
| 僅在記憶體中清空每個 `Samples[].Views`，保留其他欄位並以現行縮排格式重序列化 | **116,701 bytes**（約縮小 96.1%） |

上表由 2026-11-02 **唯讀載入**實際 Report，在記憶體內進行兩種比較；**沒有修改原始 Report**。這是結構性證據，不是已實作新 Schema 後的效能成績；重序列化及新增 metadata 可能改變最終大小。此前文件所列的 **87 samples / 5,119 views** 與逐 Item 實測不符，已更正為 **83 / 5,115**。`RawCount=68` 代表一次全域 Shell 觀測的 raw 數量，**不是單一視窗有 68 Tabs**。

### 目前程式碼及設計風險（`resume-explorer.core.ps1`）

| 位置 | 現況 | FR-6 影響 |
| --- | --- | --- |
| `Get-ExplorerObservation`（約 65–106） | 全域 Shell 列舉，建立帶有 Path、Fingerprint、Identity 與 COM 參考的 Views | **執行期仍需完整資料**做 identity／reliability 判斷；不能為縮檔直接減少安全觀測 |
| `New-DetectionDiagnostics` / `Add-ObservationDiagnostic`（約 187–202） | 每次 Sample 都複製全部 Views 的多個欄位；`Samples += ...` 逐次擴充陣列 | 重複儲存與分配成本；應改變**持久化投影**，而非核心觀測結果 |
| `Wait-StableTabBaseline`、`Wait-NewTabCandidate`、`Wait-TabNavigation`、`Wait-NewExplorerWindow` | 不同 phase 都持續呼叫 `Add-ObservationDiagnostic` | 需保留階段統計及失敗線索，不應每輪儲存完整 Views |
| `New-RestoreItem` / `New-Run`（約 283–290、376–385） | 安全旗標、原始索引、狀態、ReasonCode、Run 家族關係 | **不准移除、改變語意或受診斷資料上限截斷** |
| `Write-RestoreCheckpoint`（約 273–281） | 將整個 Run `ConvertTo-Json -Depth 32`，暫存檔加原子 Replace/Move | Checkpoint 會重寫當下**完整** Run；**並非每次 polling 都寫磁碟**；應量測序列化及寫入成本 |
| `Read-RunReport`、`Select-RetryItems`、`Get-RetryDescendantItems`（約 552–624） | Reader 目前只接受 `SchemaVersion=1`；Retry 主要靠 Status／Attempted／Run family 而非 Samples | 若變更 Samples 的契約，必須更新 Reader 且保留 V1/V2 混合家族安全性 |

## 2. 決策、範圍與不可破壞的 Invariants

**建議決策**：預設 `DiagnosticLevel=Compact`，以「有界階段摘要 + 少量有意義的事件」取代每輪全域 Views；`DiagnosticLevel=Full` 才允許有界詳細 Views Trace。**優先做最小安全改動；先不要上 sidecar、壓縮、背景 writer 或重構 Shell Observer。**

1. **Restore correctness 不變**：完整的即時 `Observation.Views`、`ReadErrors`、`IdentitySetReliable`、候選 `Seen`、WindowFingerprint 仍供內部決策；不根據已抽樣的 Report 重算 identity 或省略檢查。
2. **Checkpoint fail-closed**：`WindowCreateAttempted`、`InvokeAttempted`、`NavigateAttempted`、時間戳、`Status=OutcomeUnknown` 及 `ReasonCode`，必須在對應有副作用呼叫之前成功落盤；checkpoint 若失敗，**不得**繼續發出該副作用。精簡診斷不能改變 checkpoint 順序或異常處理。
3. **Retry 所需資料完整**：保留 `GroupIndex`、`ItemIndex`、`RequestedPath`、Status、ReasonCode、attempt flags、`WindowFingerprint`、`RunId`、`ParentRunId`、`RootRunId`、`RootReportPath`、`SourceSnapshotHash`、`SourceSnapshot`、Run State、Item/Run Error 等原有安全／稽核欄位；未知結果不得被當成未嘗試。
4. **不遺失事故可診斷性**：若 Samples 達上限，聚合計數仍更新，必要的失敗類型／HRESULT／階段／連續讀取失敗／最後可靠性仍可見；`SamplesDropped` / `TraceTruncated` 明確標記「資訊不完整」，不得假裝沒有錯誤。
5. **不更動其他需求語意**：不修改 Snapshot 格式、Restore/Retry 操作順序、UIA/COM identity、Timeout、前景焦點或 Explorer Process 管理；時序慢點的 RCA 仍由 Issue-4 處理。

## 3. 建議的 V2 報告契約

**建議新產生的 Report 使用 `SchemaVersion=2`，舊 V1 原檔保留原樣。** 因為 `Diagnostics.Samples[*].Views` 將從預設格式中移除，這是對已存在 JSON 結構的可觀察變更；不應在原 `SchemaVersion=1` 下偷偷修改其預期語意。僅修改非破壞性 optional 欄位才可維持 V1，但不符合本案主要瘦身需求。

- `Read-RunReport` 必須同時接受、驗證 V1 與 V2，明確拒絕未知版本／損壞的必要欄位；不要默默降級成 `NotAttempted` 或移除不明 attempt flags。
- V2 **保留全部 Run/Item 核心欄位**，在 `Item.Diagnostics` 中增加 `Format`、`PhaseSummaries`、`Retention`；繼續可選擇保留 `Samples` 名稱以降低測試與人工排障成本，但每個 Sample 不再隱含全域 `Views`。
- `Show-RetryPreview`、`Select-RetryItems`、`Get-RetryDescendantItems`、`Start-RetryRun` 必須支援父 V1／子 V2，及父 V2／子 V2 的家族檢查。V1 的診斷 Full Views 可照舊讀取；**不回寫、不自動遷移**歷史檔案。
- `ReportPath`、預覽檔 `.retry-preview.json` 的 SHA-256 雙向確認、Retry family lock 與 JSON 原子 checkpoint 行為不變。Preview 後 Report 若變動，仍應拒絕 Retry 並要求重新 Preview。
- 新欄位不得產生 COM Runtime Callable Wrapper、UIA Pattern 或其他不可安全序列化的執行期物件。維持 `ConvertTo-Json -Depth 32` 可跨 PowerShell 5.1/7 讀回的純 JSON 類型。

### 3.1 Compact 預設欄位（具體提案，待測試確認）

- **原有 Item／Run 資訊**：完全保留；原 `PollCount`（目前專指 Detection）、`TransientReadErrorCount`、`MaxConsecutiveReadErrors`、`DetectionElapsedMs`、`SeenCandidateCount`、`LastObservationError` 等保留可診斷的值，必要時將過大的重複錯誤文字轉為有限的 stage/HRESULT 摘要。
- **`PhaseSummaries`**：按 `NewWindow`、`Baseline`、`BeforeInvoke`、`Detection`、`BeforeNavigate`、`Navigation` 追蹤每 phase 的觀測次數、first/last elapsed、可靠／不可靠次數、read-error 次數、最後 `RawCount` / `UniqueCount`、錯誤分布與關鍵終止原因。`PhaseSummaries[*].PollCount` 與舊 `Diagnostics.PollCount` 的計數範圍必須分清。
- **`Samples`（保留的事件）**：階段首筆／最後一筆、可靠性轉變、觀測錯誤、候選從無到有／歧義、Invoke／Navigate 前關鍵觀測、超時／失敗及經 Issue-4 真正量測證實的慢呼叫。每筆限 `Phase`、`Kind`、`ElapsedMs`、`ObservedAtUtc`（按需）、`Reliable`、`RawCount`、`UniqueCount`、ErrorStage/HRESULT／候選數或安全的 target identity 摘要；**預設禁止內嵌全域 `Views` / 重複 Path / 大量 Fingerprints**。
- **`Retention`**：`SamplesSeen`、`SamplesStored`、`SamplesDropped`、`TraceTruncated`、`TruncationReason`；必要時增加估算的診斷 bytes。即便丟棄樣本，總觀測數與最嚴重錯誤數仍應正確。
- **Target identity 限制**：必要的 `WindowFingerprint` 已在 Item 層；COM `IUnknown` identity 只在交易的生命週期內有效，不作跨 Run 的永久 key。若保存 candidate id，僅供同一 Run 事後診斷，絕不能作為 Retry 重新驗證依據。

### 3.2 有界保留策略（先作可調預設，再用 benchmark 調整）

- Compact 初始建議：**每 Item 最多 12 個詳細 Samples**；先保留失敗／歧義／安全關鍵事件，保留 phase 首尾，普通重複 poll 只更新統計。若配額已滿，可替換同一 phase 的「最近一筆普通樣本」，但不得抹掉唯一的失敗事件；溢出必有 counters。
- Compact 建議診斷資料（非核心 Item/Run）**每 Run 約 128 KiB 軟性預算**；可用 incremental UTF-8 計量／在 checkpoint 重新評估，禁止在每次 poll 都重序列化整份 Run 來檢查預算。超出時只縮減可丟棄的診斷樣本，**不得截斷 JSON 文字或安全欄位**。
- `DiagnosticLevel=Full` **明確 opt-in**；可持久化多一些個別 `Views`／Errors 作排障，但仍設每 Item sample 數及整個 Run 的診斷 byte budget（初始候選約 **1 MiB**，需依實測調整），記錄遭截斷的範圍／原因。「Full」意指詳細模式，**不承諾無限量**。真要無損抓全部 Views，應另立需求評估外部 trace 檔及資安成本。
- Report 總容量 **不能是會刪除安全資訊的硬上限**：Item 數量很多或錯誤訊息很長時可以超出軟性目標；超出後明示 `BudgetExceeded` 和實際 bytes。若 quota 機制本身失敗，安全 checkpoint 應 fail-closed，不能偷偷繼續副作用。
- 先用有界陣列／List 取代未設上限的 `Samples +=` 成長，再做必要的統計；不要把問題轉成無界記憶體 buffer。細緻增量 byte accounting 可在壓測確認有實際價值後再優化。

## 4. 實作切片及順序（目前均未執行）

### Phase 0 — 基準／測試先行

1. 保留原始 Report 在個人本機，不加入 Git；建立**去識別化、結構相似的 synthetic fixture**（18 items、83 samples、5,115 累積 views，涵蓋六種 phase），並記錄原本 Report bytes／`ConvertTo-Json`／checkpoint 執行時間與寫入量。
2. 用離線 fake Adapter 建立全成功、不同錯誤、Timeout、Abort、Retry 後代、Report reader 的基準測試；比對核心 Run/Item 欄位。含使用者路徑或錯誤訊息的 fixture 以合成資料替代。
3. **Gate**：取得可重複的 bytes 基線、schema fixture、回歸測試結果；不可從原始 3 MB 一次性資料推斷 Issue-4 的耗時主因。

### Phase 1 — V2 Reader + Compact Writer（首要交付）

1. 先讓 `Read-RunReport` 能安全讀取 V1/V2（同時完整拒絕非法版本、欄位缺漏、重複 item key）；寫好新舊 Report + Retry family 的離線相容測試。
2. 在 `New-DetectionDiagnostics` 建立有界 `PhaseSummaries` / `Samples` / `Retention`；在 `Add-ObservationDiagnostic` 改成只記錄統計及選擇性事件。**不得改動傳給決策函式的完整 `Observation`**。
3. 在實際確認候選、狀態轉變、失敗分支記錄少量決策事件；關鍵診斷訊號應由既有分支產生，不靠只看 `RawCount` 反推。
4. 新報告設為 `SchemaVersion=2`、預設 Compact；`Write-RestoreCheckpoint` 仍必須在副作用之前同步原子持久化。完整保留 `New-RestoreItem`、`New-Run` 與原先 `Status`/`ReasonCode` 語意。
5. **Gate**：純離線測試通過，報告符合大小軟性目標，沒有重複 Invoke／Navigate 或錯誤 Retry eligibility，始可合併。

### Phase 2 — Full opt-in + 容量／效能驗證（有條件實作）

1. 在 `resume-explorer.ps1` 的參數與 `Config` 增加 `DiagnosticLevel`（建議 `Compact`/`Full`），預設與舊命令相容；為 Full 設明確限制、截斷原因及容量統計。
2. 量測精簡前後：**每次** checkpoint 的 serialize ms、write/replace ms、peak report bytes、累計寫入 bytes、peak memory、單 Item 耗時；將診斷／I/O overhead 與真正 Shell/COM 觀測耗時分開（參照 Issue-4）。
3. 優先不使用 sidecar。只有實證顯示 Full 模式會拖慢安全 checkpoint，才另作 sidecar/壓縮 Spike；sidecar 失敗或遺失**不得影響** Report 認定、PreviewRetry、Retry 或 checkpoint。
4. **Gate**：Full cap 實測有界、截斷告知完整；效能沒有顯著退化。若達不到，僅保留已驗證的 Compact MVP，不拖延核心縮檔改進。

### Phase 3 — 整合與文件更新

1. 離線測試可由 GitHub Actions Windows runner 跑 mock／schema／byte budget；Shell GUI E2E 必須在可重設的互動 Windows VM 執行，不依賴 hosted CI 中的真實 Explorer 桌面。
2. 更新 `README.md` 的 Report Schema、DiagnosticLevel、容量、Privacy、Retry 版本相容性，並更新 `Backlog.md` 與驗證記錄。
3. **不在日常使用中的 Explorer／VDI 自動 Restore 壓測**；不殺 `explorer.exe`、不清理未知 PID、不修改真實報告與 Snapshot。

## 5. 測試矩陣與驗收標準

| 測試 | 必要結果 |
| --- | --- |
| 真實規模 synthetic 18/83/5,115；20/50/100+ 全域 Views | Compact 不再持久化每輪全域 Views；聚合計數和總 polling 數正確 |
| 單 Phase 很長、全部觀測可靠但內容重複 | Sample 數量有界，first/last/計數仍能表示經過時間和重複觀測 |
| 不可靠 Observation／IdentityConflict／重複 Path／多 candidates／Path unreadable | 原判斷與 reason 不變，關鍵 error stage/HRESULT 仍可診斷 |
| `WindowCreateAttempted`／`InvokeAttempted`／`NavigateAttempted` 後中斷或 checkpoint 失敗 | 不會因診斷裁剪遺失 `OutcomeUnknown`，未寫入成功時不執行副作用 |
| Compact / Full 達 sample 及 byte budget | JSON 可讀，無安全欄位被裁掉，`TraceTruncated` 和 dropped counters 準確 |
| 舊 `SchemaVersion=1`；新 V2；V1 父/V2 子 Retry family | Reader、PreviewRetry、Retry eligibility 和 descendant 判定一致；非法版本 fail-closed |
| V1/V2 UTF-8、繁體中文／emoji、UNC、重複路徑、長 Path、PowerShell 5.1/7 | Round-trip 不修改原始 `RequestedPath`、Index、Status、Attempted 或 Run lineage |
| Report 中途寫入失敗、舊版 Report 已被 Preview、Read-only／locked file | 原子 checkpoint／hash guard 維持；報錯不造成重送／重複副作用 |
| Snapshot Capture/Preview + 現有 `tests/Issue2.Tests.ps1`、`tests/RestoreSummary.Tests.ps1` | 舊功能及 mock single Invoke / Navigate tests 全部通過，無真實 Explorer 副作用 |

**量化驗收（soft target，須實測修正）**：

- 18-items 相同規模下，Compact **≤300,000 bytes**（約比原報告縮小 ≥90%），不得以裁切核心欄位「達標」；若未達標，先分析真正佔比。
- 在相同假資料、硬體及重複測試下，checkpoint 序列化／寫檔的 P50/P95、累計寫入 bytes、記憶體占用，至少不得出現顯著的新 regression；若無法可靠量測，明示數據不足，**不宣稱已提升 Restore 速度**。
- 所有既有 Issue-2 identity、single-invoke、checkpoint、OutcomeUnknown、Retry tests 及 V1/V2 新增相容測試通過；報告仍能獨立被讀取，Full trace 不是 Retry 依賴。
- 未登入 GUI 的 CI 只驗證離線正確性；真實 Explorer/VDI E2E 另記實測，且不可影響使用中的視窗。

## 6. 與 Issue-4 的接口及待決事項

- **FR-6 負責**：Persisted Report 投影、容量控制、schema/version、診斷抽樣、checkpoint 序列化成本與舊版 reader 相容。
- **Issue-4 負責**：真實 `ObserveDurationMs`、單次 COM/UIA Stage duration、deadline overrun、同步阻塞的 RCA／timeout correctness。新增 timing 欄位時共用 `PhaseSummaries` 契約，**不能把 `ElapsedMs` observation timestamp 誤當單次 Observe 耗時**。
- **待實作前確認**：上述 12 samples/item、128 KiB Compact、1 MiB Full 是**初始配置候選，不是不可調的硬規格**；先用 synthetic fixture 和真實規模測量，再調整。是否需要 Full sidecar 也以實測成本決定。
- **Rollback**：如 V2/Compact 對 Retry 或故障檢查造成任何不可接受的 regression，回退新 writer、保留 V1 Reader 支援；不應為省空間削弱 identity／checkpoint 安全性。
