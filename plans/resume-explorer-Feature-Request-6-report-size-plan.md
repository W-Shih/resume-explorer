# Feature Request-6 — JSON Report 容量與保留策略：實證導向調查／有條件優化

- 初稿：2026-11-01；決策更新：2026-11-02
- 優先級：**P2（建議；如證實核心效能或儲存問題再升 P1）**
- 狀態：**Reviewed / Proposed；尚未實作、尚未驗收**
- 目的：在保留完整安全紀錄與事故診斷能力的前提下，量測 Report 對磁碟、記憶體與 checkpoint 的實際成本，再決定最小改善
- 與 [Feature Request-9](resume-explorer-Feature-Request-9-diagnostic-level-plan.md) 分工：**FR-6 管理容量證據與歷史檔案保留；FR-9 定義 Compact 預設／Full opt-in 的診斷等級需求**。FR-6 不預先承諾 Schema V2 或 Compact Writer

## 1. 為何調整方向（保留已驗證的事實）

2026-11-02 曾以唯讀方式分析一份真實 Restore Report（包含使用者路徑，不得加入 repo）；以下僅為該案例的容量證據，**不能推論整個工具的效能瓶頸**：

| 指標 | 唯讀觀測／記憶體重序列化 |
| --- | --- |
| 原始 Report | **3,002,321 bytes**（約 3.00 MB／2.86 MiB） |
| Restore Items | **18**；13 Verified、1 OutcomeUnknown、4 NotAttempted |
| 診斷 Samples / 累積 Views | **83** Samples／**5,115** 次 Views 儲存（非 unique Views） |
| 僅使用 `ConvertTo-Json -Compress` | **1,514,104 bytes** |
| 僅在記憶體中清空 `Samples[].Views` 再縮排序列化 | **116,701 bytes** |

此結果確認 **`Add-ObservationDiagnostic` 持續複製全域 Explorer Views 是單份 JSON 變大的主要來源**；原始 Report 未遭修改。它**沒有**量測 checkpoint 耗時、磁碟累計寫入、峰值記憶體，也**沒有**證明 Issue-4 `NavigationTimeout` 的根因是 JSON。

現有程式碼行為（`resume-explorer.core.ps1`）：

- `New-DetectionDiagnostics`／`Add-ObservationDiagnostic` 保留每次全域 Views 和 Errors，`Samples +=` 會逐步增加記憶體內診斷資料。
- `Write-RestoreCheckpoint` 每次將**當下完整 Run** 用 `ConvertTo-Json -Depth 32` 序列化，再以同目錄暫存檔 Replace/Move；**不是每個 polling 都寫一次檔**。
- `New-Run` 目前寫入 `SchemaVersion=1`，`Read-RunReport` 只接受 V1。`PreviewRetry`／`Retry` 使用 Report、來源 hash、指紋、attempt flags 與 Retry 家族。
- 故單純限制「只留下 3–5 份歷史檔案」可能有效控制**長期磁碟累積**，但**不會降低正在執行的 Run 的序列化／記憶體成本**。

## 2. 決策與不變量

**當前決策：先保留現行 Full 等級的 V1 JSON Report，不立即修改診斷內容或 Report Schema。** 若實測只有磁碟歷史累積問題，優先考慮安全的 Report Retention；如證實單次執行時診斷成本明顯，將數據交由 FR-9 評估 Compact/Full 的實作優先序。

不可破壞：

1. **JSON Report 是核心安全功能**，不能為節省空間而關閉 Run／Item `Status`、`ReasonCode`、`WindowCreateAttempted`、`InvokeAttempted`、`NavigateAttempted`、原始 Group/Item 索引、RequestedPath、WindowFingerprint、Run/Root/Parent lineage 等欄位。
2. 在有副作用的 WindowCreate／Invoke／Navigate 前，仍需成功持久化 `OutcomeUnknown`／attempt flags 的**原子 checkpoint**；失敗時不得繼續副作用。
3. 保留 `PreviewRetry` SHA-256 hash guard、Retry family lock、已完成後代阻止重試與 `IncludeUncertain` 保護；清理不可讓原本已 Verified／Attempted 的項目被誤認為安全可重送。
4. 不修改 Snapshot 格式、既有 CLI、Explorer Observation／identity 決策，也不將 `ElapsedMs` 相對標記誤當單次 COM Observe 耗時。
5. 只讀量測、不清理日常 Explorer、不對使用中的 Explorer/VDI 做自動 Restore 壓測；報告含敏感 Path/Errors，不能提交真實 JSON 到公開 repo。

## 3. Phase 0 — 量測與可重現基線（首要工作）

1. **磁碟側**（唯讀）：按 Report／Root Run family 整理數量、檔案大小、累計 bytes、時間分布、P50/P95／最大 family 大小、失敗／未確認項目的比率。記錄是否有自訂 `-ReportPath`、Pinned／調查中的 Report；不要在測量輸出中列出真實 RequestedPath。
2. **單次執行成本**：以合成、去識別化 fixture 建立至少 18 items／83 samples／5,115 累積 views 的基線，另測 20／50／100+ 全域 Views、長 polling、巨大錯誤文字與多組 Retry。分開測量 `Add-ObservationDiagnostic`、`ConvertTo-Json`、write/replace 時間、單次／累計寫入 bytes、checkpoint 次數、峰值記憶體與 Full 報告大小。
3. **控制變因**：用相同假資料、相同 PowerShell 版本／硬體與多次執行取得 P50/P95。保留同一份資料的 in-memory Compact projection 比較作為**估算選項**，不能把 116,701 bytes 的模擬結果當成已交付的改善。
4. **與 Issue-4 分離**：以明確的時間邊界衡量 checkpoint 與 Shell COM/UIA 同步操作，不因單一 3 MB 案例就認定 checkpoint 導致 Timeout。
5. **基線驗證**：跑既有離線測試並保存原有失敗情況。2026-11-02 文件 Review 時，`tests/Issue2.Tests.ps1` 曾回報 **39 PASS**；`tests/RestoreSummary.Tests.ps1` 在 **S16 checkpoint-failure 訊息斷言**中止（S01–S15 PASS）。這是當時的既有基線，未證實為 FR-6 相關 regression；不得為求通過而削弱測試。

**Phase 0 Gate：**有可重複的容量／時間基線、與 JSON 相關的耗時占比、使用者實際保留需求，以及可審核的安全測試；不足時維持 V1 Full，不做推測性優化。

## 4. Phase 1 — 安全的歷史 Report Retention（僅在磁碟成本有必要時實作）

**候選策略：**保留最近 **3–5 個完整 Root Run Families**（預設數量待量測），不是機械地保留 3–5 個 JSON 檔。每個 family 包含 Root Report、`RetryRuns` 中相關子孫 Report 與對應的 retry-preview／lock sidecars；這與 FR-9 所說的**單份 Report 內的診斷 Sample 保留**是不同概念。

1. **先建立可查閱清單與 DryRun／Preview**：列出預計保留／清除的完整 family、數量、bytes、狀態與原因；不展示 Path 等敏感內容。初期只允許明確 opt-in 清理，不能在使用者執行一般 Restore 時偷偷刪除舊 JSON。
2. **一致性優先**：分析 `RunId`、`ParentRunId`、`RootRunId`、`RootReportPath` 和實際目錄關係；先完整驗證 family graph／檔案歸屬，**再**將整個 family 視作可清理單位。部分損壞、孤兒或跨目錄不明依賴一律跳過並提示，不猜測。
3. **嚴格清理邊界**：僅能管理工具明確擁有的報告目錄；**自訂 `-ReportPath`、手動保留檔、目錄外檔案與 Snapshot 永遠不可被預設自動清理**。不得沿著 Report 內可被任意改寫的路徑進行未驗證的刪除。
4. **避免破壞未完成工作**：執行中、正被 PreviewRetry／Retry 使用、locked、含 `OutcomeUnknown`、`Aborted`、無法判斷是否尚需重試、使用者指定 pin 的 family，預設不自動清除；必要時讓可保留總量超過候選 3–5，不應把數量上限視為刪除安全紀錄的硬命令。
5. **競態與失敗**：清理需再次檢查 family 狀態、權限與活躍鎖；遇到競態或部分刪除風險時 fail-closed，不清理未確認對象。不得刪除其他程序的 lock 或中斷有效 Retry；如需跨檔刪除的 crash-recovery 協定，另做小型設計／測試，不假定多檔刪除具有原子性。
6. **容量限制**：保留 5 個 families 不代表固定 15 MB；須考慮每個 family 的子代數與異常大型 Report。若保留策略仍不能控制容量，先呈現超標事實與建議，不能刪除安全欄位或強制清理受保護的 family。

**Phase 1 Gate：**同時涵蓋乾跑、有效／失敗／損壞的 Root＋Child family、preview hash、活躍 Retry、併發建立、手動路徑、OutcomeUnknown、孤兒、磁碟權限與寫入中斷等離線測試；在安全性未驗證前不得設定預設自動清理。

## 5. Phase 2 — 根據實證作選擇（不預設要修改 Schema）

| 觀測結果 | 建議決策 |
| --- | --- |
| 僅長期磁碟檔案累積造成負擔 | 考慮 Phase 1 Retention；保留現有 V1 Full writer |
| checkpoint／診斷記憶體成本反覆且明顯影響執行 | 將效能證據交給 **FR-9**，評估 Compact Default／Full opt-in、可能的 V2 Schema |
| RCA 必須依賴完整每輪 Views，但磁碟成本有限 | 暫時保留 V1 Full；先強化 Retention／手動診斷流程 |
| 磁碟與執行時成本都不顯著 | 記錄 No Change／Deferred 結論；不得為達成縮檔目標而無必要地改變程式 |

同規模 Report 僅在記憶體移除 Views 可降至約 117 KB，是**FR-9 的可行性證據**，不是 FR-6 的必須交付目標。原先「每 Item 12 Samples／128 KiB／1 MiB／Compact ≤300 KB」等候選移至 FR-9 的可選設計，**不作 FR-6 驗收門檻**。

## 6. 驗收、分工及歷史決策

- **FR-6 驗收**：提供容量／checkpoint 成本基線與清楚的有／無修復決策；若實作清理，必須證明不破壞完整 Run family、安全 Retry、現有 JSON 可讀性及使用者自訂檔案。
- **FR-9**：定義 Report 診斷等級、持久化投影、必要時的 Schema 變更、V1/V2 reader 與診斷取樣；實作需參考 FR-6 的量測和自身驗收條件。
- **Issue-4**：獨立調查同步 COM/UIA 階段耗時與 Deadline correctness；不能因 FR-6 的報告縮小而宣稱 Issue-4 已修復。
- **Task-1**：離線 mock／family 合約與回歸測試，Windows Explorer E2E 只在隔離的可重設互動環境進行。
- **Rollback**：Retention 若存在任何不確定性，先關閉清理功能而不改動既有 Report；不可透過刪除證據修復故障。
- **歷史決策**：此前曾規劃「立即導入 Compact V2／雙版本 Reader」。2026-11-02 使用者將該實作方向**移到獨立 FR-9**，FR-6 改成**先量測、再決定**。本次僅文件改動，不代表已完成效能改善、V2 遷移或任何自動清理。
