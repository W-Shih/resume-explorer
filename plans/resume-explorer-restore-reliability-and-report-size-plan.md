# Resume Explorer — Focus Independence, Synchronous Timeout & Report Size 改善計畫

- 日期：2026-11-01
- 狀態：設計與 RCA 規劃；**未修改產品程式、未進行實際 Restore**
- 對應：`Backlog.md` Issue-3、Issue-4、Feature Request-6
- 來源案例：`02e5f26b61da4a1ba503bea37d15323f.json`；請勿將包含實際使用者目錄的完整 Report 提交至公開儲存庫

## 1. 已知事實與尚待驗證的推論

案例為 18 items：13 `Verified`、1 `OutcomeUnknown / NavigationTimeout`、4 `NotAttempted`，皆位於 Group 6 的未驗證序列。Tab 3 已嘗試 Invoke 與 Navigate，項目歷時 28,545 ms。Navigation 只有一筆 observation，標示 elapsed 15,813 ms、`RawCount=68`、`UniqueCount=68`、`Reliable=True`；該觀測的 Views 中包含要求的目標路徑，但**不能僅憑路徑存在就認定新候選 Tab identity 已被穩定驗證**。

這份 JSON 精確大小為 **3,002,321 bytes**（約 **3.00 MB / 2.86 MiB**），包含 **18 items、87 筆 Diagnostics.Samples、共 5,119 筆儲存的 Views**。這是「全域清單反覆快照」可能造成膨脹的強烈證據，但完整的位元組占比仍需精確量測，不能直接宣稱所有大小皆來自 Views。

目前 `Get-ExplorerObservation()` 會透過 `Shell.Application.Windows()` 枚舉全域 Shell 視窗／分頁，再記錄 Path、HWND、fingerprint、identity 等資訊；`Add-ObservationDiagnostic()` 會在每次 sample 保存 Views 與 Errors。觀測呼叫屬同步執行，現有輪詢 deadline **不會強制中斷一個卡住的 COM/UIA call**。目前尚未證明是滑鼠切焦點，或「單個 Explorer 視窗 Tab 太多」，造成這次超時。RawCount=68 也不等於已確認有 68 個單一視窗內的 Tabs。

## 2. Issue-3：Restore 不應受無關滑鼠焦點影響

**產品不變量**：單純將 Chrome／Visual Studio／其他應用帶到前景，不應使正在還原的 Tab 被導覽到錯誤路徑、錯認 identity、或因焦點切換本身而失敗。既有設計使用 UIA InvokePattern、Shell COM Navigate2 與身份觀測，並不依賴 SendKeys 或滑鼠座標；此為預期設計，**尚未通過完整實機回歸驗收**。

區分：(A) 只變更其他應用前景；(B) 切換另一個 Explorer 視窗；(C) 在同個目標 Explorer 切換 active Tab；(D) 手動在目標視窗新增／關閉 Tab；(E) 關閉目標視窗。A/B 應盡量不影響；C 需驗證；D/E 改變共享狀態，若造成 candidate ambiguity／window loss，應停止且不猜選。這與 Feature Request-1 的「Restore 自身不搶焦點、不彈視窗」不同。

**驗證**：建立可控的多視窗測試矩陣，在相同 Snapshot、Tab 數量、VDI 負載及 timeout 下，對照無互動與 A–E；記錄 elapsed、candidate identity、path 及原因碼。測試不得藉由放寬驗證來製造假成功；不得誤導到其他現有分頁。若 A/B 可靠重現失敗，再追查 UIA Invoke 或 COM 的 active-tab 相依性。

## 3. Issue-4：同步操作／NavigationTimeout RCA 與修復方向

### 3.1 Phase 1 — 效能儀表化（優先）

在不改 restore 行為的前提下量測：`ObserveStartedAt`、`ObserveDurationMs`、`ShellWindowsEnumerateDurationMs`、每筆慢的 `FullName/HWND/Fingerprint/Identity/Path` 階段、`ObservedViewCount`、`DeadlineRemainingBefore/After`、`DeadlineOverrunMs`。避免預設持久化全部路徑：慢步驟以 stage、耗時、HRESULT、目標 HWND／索引等診斷表示，敏感資訊放在 opt-in 詳細模式。

特別區分「observation 開始時已有超時」與「同步 COM call 在 deadline 之內開始、卻於 deadline 之後才返回」；保留純 monotonic stopwatch。由單一 observation 的耗時與前後 timestamps 證明阻塞點，而非由 Sample 的 elapsed label 直接推斷完整函式耗時。

### 3.2 Phase 2 — 降低同步工作量

先用 profiler/trace 確認是否反覆枚舉全域 68 個 Shell 物件或某一個 COM property 存取特慢。研究可否以 target HWND 篩選後減少不必要的 Path/Fingerprint 讀取，但不能降低「全域觀測完整性」及 duplicate／candidate identity 的安全性。任何 target-aware fast path 必須證明可以區分同一個目標視窗所有 baseline/new tabs，並且遇到未完整觀測仍保守停止。測試高 Tab 數、多個 Explorer 視窗、共享路徑及 slow COM property。

### 3.3 Phase 3 — 有界同步呼叫隔離（只在證據支持時）

如果 COM call 長時間阻塞，僅把 `NavigationTimeoutSeconds` 從 10 調到 20/30 秒只能延後失敗；無法保證有界等待。研究獨立 process/STA worker 與通訊 deadline、生命週期及停止協定；若 caller 超時，對曾經發出的副作用（Invoke/Navigate）須維持 `OutcomeUnknown`，不可在未確認前自動重發。不得使用 `Thread.Abort` 等任意中斷方式，亦不得為了取消 worker 而殺死 `explorer.exe`。

### 3.4 Acceptance

- 可準確呈現每次 Observe 的實際耗時與 deadline overshoot；長 COM call 不會被誤判成只發生很多次 polling。
- 高負載測試包含全域 20/50/100+ 個 shell view（測試參數，非效能保證），並保留 600 ms 穩定驗證與候選單一性。
- 不再因單純 A/B 焦點切換而錯選 Tab；C/D/E 若確定有歧義仍安全中止。
- 恢復成功率與耗時需以基準測試量化；不承諾在 Windows COM 不合作時實現硬性 wall-clock SLA。
- 不改原始 Group/Item 索引、checkpoint、single Invoke/Navigate 及 Retry 風險控制。

## 4. Feature Request-6：減少 JSON Report（優先級高）

### 4.1 目標與預算

預設報告採 **Results + Compact Diagnostics**：每個 Item 保留狀態、原因、attempt flags/timestamps、原始 Group/Item、Path、必要 window fingerprint 與 error；每個 phase 保存 count、耗時、最後可靠性、最大／最慢觀測、error count、candidate count、timeout reason。**不要每次 poll 都重複儲存全域所有 Views**。

建議先設**非硬性效能目標**：對 18 項、數十個 Explorer Views 的相同測試情境，預設報告力求不高於 **300 KB**（比 3.00 MB 減少約 90%）；如要保留特殊失敗證據，優先使用 bounded samples，而非破壞安全資料。目標須以實測調整，不能直接把報告截斷成無效 JSON。

### 4.2 資料策略

1. 預設只儲存聚合統計和重要 state transitions（baseline stabilized、Invoke checkpoint、candidate confirmed、navigation started、navigation verified／timeout、identity conflict）。對每 phase 留首筆、最後一筆、錯誤前後和慢呼叫等**有限樣本**。
2. 將「全域 Views 每次樣本完整清單」改為：必要候選 identity／target HWND／target path，以及 counts/hash/delta；原始全域 trace 僅在 `DiagnosticLevel=Full` opt-in（參數名稱可再決定）保存。
3. 為 full trace 設 sample／byte budget，超出後記錄 `SamplesDropped`、`TraceTruncated`、實際收集範圍與 truncation 原因；**原子 checkpoint 與每個 Item final status 不得被截斷**。
4. 如需進一步縮小，可選 compact JSON（移除不必要縮排）或診斷 sidecar 壓縮，但優先除去冗餘。不要讓 Retry 依賴 sidecar 的存在；不要用不受限制的記憶體緩存取代逐項 checkpoint。
5. 除了 bytes，也需量測每次 checkpoint 序列化／寫檔時間與總寫入量。現有 checkpoint 每次重寫整份 JSON，過大的 trace 可能放大同步 I/O 等待；這是待量測的可能成本，不能先認定是本次 NavigationTimeout 根因。
6. 報告包含使用者路徑、視窗資訊等；不要上傳完整真實 trace 到公開 Git repository。測試使用合成路徑或適當匿名化資料。

### 4.3 Schema、Retry、舊報告相容性

優先保持 `SchemaVersion=1` 及既有必要欄位；若 `Diagnostics.Samples` 結構發生不相容變更，應明訂新 schema version、文件與舊版讀取策略，而非偷偷將舊欄位移除。尤其 `Read-RunReport`、`Show-RetryPreview`、`Select-RetryItems`、`Get-RetryDescendantItems` 和 checkpoint 中斷後的 `OutcomeUnknown` 必須保持安全運作。Report 保持可單獨閱讀；Full trace 不得成為 Retry 的硬依賴。

### 4.4 離線及實機測試

- 合成 18 items × 87 samples × 68 views 的舊式 fixture，記錄 baseline bytes、序列化時間、peak memory；新設計檢查 bytes 比例與資料完整性。
- 全成功、部分未驗證、`Aborted`、重複路徑、error/ambiguous samples、`OutcomeUnknown`、大批 items、多個 child retry reports。
- Full 與 Compact 模式各自測試 size budget、truncation metadata、UTF-8、PowerShell 5.1/7 JSON round-trip、保留原始路徑及 Unicode。
- 檢查 `PreviewRetry/Retry` 對既有 Schema1 報告的相容性；不得因資料縮減允許重複建立或漏判不確定狀態。
- 真實 VDI 僅在隔離測試環境做 Restore；不在目前使用中的 Explorer 上自動壓測。

## 5. 建議執行順序

1. **P1：精簡 Report**（先建立大小與 checkpoint cost 基準；改善資料保存膨脹，使後續 instrument 更可負擔）。
2. **P1：Observation timing RCA**（可與 Report 設計一起做，在 compact summary 保留量測）；只有定位慢點後，才評估同步呼叫隔離／target observation。
3. **P2：焦點互動矩陣**（先作為 reliability acceptance，若 A/B 可重現錯誤再提高至修復優先級）。

三項可以分開 commit；先建立針對新診斷與 JSON 累積量的 deterministic tests。現有核心 Issue-2 的實機 acceptance、可見性 regression 及背景不搶焦點 Feature Request-1 均保持獨立追蹤。

## 6. 變更約束與完成定義

- 本文件是**待實作規劃**，不聲稱目前已修復同步超時、已不受焦點影響或已把 Report 壓縮。
- 每項改動都先做 unit/integration tests，再在可隔離的 Windows Explorer 情境進行 controlled E2E；保留原本單次 Invoke、保守身份驗證、checkpoint 及 Retry 安全性。
- 完成時更新 `Backlog.md`、`README.md`、`ISSUE2-VALIDATION.md` 並附精確 benchmarks、測試數量與版本；只做完文件不標示為 Done。
