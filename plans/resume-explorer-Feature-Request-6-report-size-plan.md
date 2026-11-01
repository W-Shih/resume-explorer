# Feature Request-6 — 精簡 JSON Report 與診斷資料計畫

日期：2026-11-01；狀態：待實作／待驗證；**本次僅拆分文件，不改 Restore 程式碼**。

來源案例：`02e5f26b61da4a1ba503bea37d15323f.json`。真實 Report 含使用者路徑，不得提交公開 repo。

對應：`Backlog.md` Feature Request-6（P1）。

## 實際大小基準

Report 大小 **3,002,321 bytes**，18 items、87 Diagnostics.Samples、5,119 個儲存的 Views。重複全域快照可能是主要來源，實際位元組占比仍需量測。

## JSON Report 瘦身方案

### 1 目標與預算

預設報告採 **Results + Compact Diagnostics**：每個 Item 保留狀態、原因、attempt flags/timestamps、原始 Group/Item、Path、必要 window fingerprint 與 error；每個 phase 保存 count、耗時、最後可靠性、最大／最慢觀測、error count、candidate count、timeout reason。**不要每次 poll 都重複儲存全域所有 Views**。

建議先設**非硬性效能目標**：對 18 項、數十個 Explorer Views 的相同測試情境，預設報告力求不高於 **300 KB**（比 3.00 MB 減少約 90%）；如要保留特殊失敗證據，優先使用 bounded samples，而非破壞安全資料。目標須以實測調整，不能直接把報告截斷成無效 JSON。

### 2 資料策略

1. 預設只儲存聚合統計和重要 state transitions（baseline stabilized、Invoke checkpoint、candidate confirmed、navigation started、navigation verified／timeout、identity conflict）。對每 phase 留首筆、最後一筆、錯誤前後和慢呼叫等**有限樣本**。
2. 將「全域 Views 每次樣本完整清單」改為：必要候選 identity／target HWND／target path，以及 counts/hash/delta；原始全域 trace 僅在 `DiagnosticLevel=Full` opt-in（參數名稱可再決定）保存。
3. 為 full trace 設 sample／byte budget，超出後記錄 `SamplesDropped`、`TraceTruncated`、實際收集範圍與 truncation 原因；**原子 checkpoint 與每個 Item final status 不得被截斷**。
4. 如需進一步縮小，可選 compact JSON（移除不必要縮排）或診斷 sidecar 壓縮，但優先除去冗餘。不要讓 Retry 依賴 sidecar 的存在；不要用不受限制的記憶體緩存取代逐項 checkpoint。
5. 除了 bytes，也需量測每次 checkpoint 序列化／寫檔時間與總寫入量。現有 checkpoint 每次重寫整份 JSON，過大的 trace 可能放大同步 I/O 等待；這是待量測的可能成本，不能先認定是本次 NavigationTimeout 根因。
6. 報告包含使用者路徑、視窗資訊等；不要上傳完整真實 trace 到公開 Git repository。測試使用合成路徑或適當匿名化資料。

### 3 Schema、Retry、舊報告相容性

優先保持 `SchemaVersion=1` 及既有必要欄位；若 `Diagnostics.Samples` 結構發生不相容變更，應明訂新 schema version、文件與舊版讀取策略，而非偷偷將舊欄位移除。尤其 `Read-RunReport`、`Show-RetryPreview`、`Select-RetryItems`、`Get-RetryDescendantItems` 和 checkpoint 中斷後的 `OutcomeUnknown` 必須保持安全運作。Report 保持可單獨閱讀；Full trace 不得成為 Retry 的硬依賴。

### 4 離線及實機測試

- 合成 18 items × 87 samples × 68 views 的舊式 fixture，記錄 baseline bytes、序列化時間、peak memory；新設計檢查 bytes 比例與資料完整性。
- 全成功、部分未驗證、`Aborted`、重複路徑、error/ambiguous samples、`OutcomeUnknown`、大批 items、多個 child retry reports。
- Full 與 Compact 模式各自測試 size budget、truncation metadata、UTF-8、PowerShell 5.1/7 JSON round-trip、保留原始路徑及 Unicode。
- 檢查 `PreviewRetry/Retry` 對既有 Schema1 報告的相容性；不得因資料縮減允許重複建立或漏判不確定狀態。
- 真實 VDI 僅在隔離測試環境做 Restore；不在目前使用中的 Explorer 上自動壓測。



## 相關工作與共通保護

- 保留 Issue-2 的單次 Invoke／Navigate、Tab identity、原子 checkpoint、OutcomeUnknown 與 PreviewRetry／Retry 安全規則。
- 在隔離 Windows 測試環境執行 E2E，不直接於使用中的 Explorer 壓測；完成後更新 Backlog、README 與驗證紀錄。

- Observation latency 的詳細量測與 timeout policy 由 Issue-4 負責；其所需的摘要型 timing 欄位應與此計畫共同設計。
