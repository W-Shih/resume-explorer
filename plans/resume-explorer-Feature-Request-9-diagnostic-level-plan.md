# Feature Request-9 — JSON Report 診斷等級：日常 Compact／調查 Full

- 建立：2026-11-02
- 優先級：**P2（建議；可依 FR-6 效能證據調整）**
- 狀態：**Feature Requirement / Proposed；尚未設計定案、未實作**
- 範圍：保留 JSON Report 核心功能，在**實作本功能後**讓一般使用預設 Compact，針對 RCA 可明確選擇 Full
- 依賴：參考 [FR-6 容量／保留策略量測](resume-explorer-Feature-Request-6-report-size-plan.md)；本功能不應成為 FR-6 量測或安全 Retention 的前置條件

## 1. 需求與定位

**核心使用情境：**日常 Restore 應有體積較小且足以理解結果／基本錯誤的 JSON；深入 Debug／RCA 時應可明確要求與目前 Full V1 Report 盡可能等價的詳細 Shell Views／Errors，以便事故發生後分析。

1. JSON Report **在兩種模式下都必須產生**；不提供「為縮小檔案而不記錄安全 checkpoint」的選項。
2. **Compact（目標預設）**：保留全部 Run／Item 狀態與 Retry 不變量、輕量階段統計及必要的錯誤／候選／歧義線索；**不在每個 Sample 重複持久化全域 Views**。即時完整 `Observation.Views` 仍由安全決策使用，不受儲存格式改變。
3. **Full（明確 opt-in）**：盡可能保留現行診斷能力，包括詳細 Views／Errors（可能包含其他視窗敏感 Path）；是否限制總筆數／大小須由效能與故障診斷需求量測決定，若有截斷需顯式標記，**不能宣稱無界或 100% 無損**。
4. 兩種模式**同一個 Report 契約、同一套 Reader／Retry 安全邏輯**，每個 Run 只產生一份 JSON Report；不應為一種模式另外製作缺少安全欄位的第二份檔案。
5. Full **不能事後補回** Compact 當時沒有保存的資料。因此 Compact 必須足以調查常見的失敗類型；若需要完整事故前 Views，使用者須在重現前選擇 Full。
6. 與 **FR-6 的 file retention 獨立**：切換 Compact／Full 不會自動刪除或輪替歷史檔案，不能以節省磁碟為理由移除歷史 Retry 證據。

## 2. 對外介面（提案，非現有功能）

建議沿用 PowerShell 語意，新增可選參數 `-DiagnosticLevel Compact|Full`，目標為：

```powershell
# 本 FR 實作完成後的期望行為（目前尚未支援）
.\resume-explorer.ps1 -Action Restore
.\resume-explorer.ps1 -Action Restore -DiagnosticLevel Full
```

- 未提供參數時等同 Compact；一般既有命令列不需修改。`-Action Retry` 亦要明確定義當次子 Run 的診斷等級，不得悄悄改變來源 Report 的儲存內容。
- 不使用 `-Verbose` 代表 JSON 診斷等級：`[CmdletBinding()]` 已提供 PowerShell Common Parameter `-Verbose`，用途為控制即時訊息輸出。
- 開發前先確認實際外部消費者對 `Diagnostics.Samples[].Views` 的依賴；即使 CLI 不變，JSON 格式仍可能是 breaking change。

## 3. Schema、安全及相容性原則

- **目前仍為 V1 Full**：`New-Run` 產生 `SchemaVersion=1`，`Read-RunReport` 目前僅接受 V1。此 FR 不假設 V2 已實作。
- 若移除或改變 `Samples[].Views` 的預設結構，應使用明確的新 Schema 版本（**V2 是候選，不預先批准**）；同一 V2 可以在 `Diagnostics` 標記 Compact／Full，不應把兩種模式拆成彼此不相容的 Report 家族。
- Reader／PreviewRetry／Retry 必須可讀歷史 V1 及新版 Report；原始 Group/Item、`Status`、`ReasonCode`、`WindowFingerprint`、attempt flags、`RootRunId`／`RootReportPath`、SHA-256 Preview hash 與子孫 Retry 查核不能退化。缺漏或型別不可信的 attempted 欄位必須 fail-closed。
- `WindowCreateAttempted`／`InvokeAttempted`／`NavigateAttempted` 及 `OutcomeUnknown` 在副作用**之前**成功原子 checkpoint；任何診斷截斷不得影響核心欄位、Report JSON 完整性、重試 eligibility 或副作用次數。
- 診斷階段可以採小型事件摘要、錯誤 Stage/HRESULT、可靠性變化與候選歧義，但不得用抽樣資料代替即時完整 Observation 做身份判斷。
- Full 如設 Sample／byte budget，須分別計數「正常略過」和「容量限制而丟棄」，保留有意義的錯誤與 `TraceTruncated` 訊號；不能只為達成固定 byte 上限裁掉安全欄位。
- 報告可能含個人／公司目錄及錯誤訊息，Full 使用者須明確知悉隱私與容量成本；任何 fixture 均應去識別化。

## 4. 實作前的 Evidence Gate

1. 先完成 FR-6 的 Full baseline：單份及歷史總 bytes、樣本分布、checkpoint `ConvertTo-Json`／磁碟寫入成本、峰值記憶體、長 polling／Errors 與 RCA 可用性。
2. 以 **in-memory Compact prototype** 和去識別化 synthetic 報告比較大小、診斷可用性與時間成本；先確認既有 `Samples.Views` 的保留是否真的對常見 RCA 必要。
3. 如只有磁碟累積問題、且 Full 的執行成本低，可先延後 FR-9 實作，不因此將 FR-6 視為未完成；若反覆確認有顯著執行期成本，再提高 FR-9 優先序。
4. 當決定實作時，先新增 schema／Report mode／mixed V1-V2 Retry family／Preview hash／atomic checkpoint 的離線回歸測試，再分離實作 Compact Writer 與 Full opt-in，避免一次改動 Observer、Retry 與 UIA。
5. 本功能可能需要更新 README、版本號、JSON 消費者遷移指引及原測試對 Schema V1 的硬編碼斷言；**不可為通過測試而直接放寬既有安全斷言**。

## 5. 驗收準則（有條件實作時）

| 項目 | 必要結果 |
| --- | --- |
| 預設與 CLI | 不傳參數即可取得 Compact；顯式 Full 可取得更詳細診斷；原有 Capture／Restore／Retry 命令仍可用 |
| 核心安全 | 兩種模式對相同 synthetic Observation 的 Restore 狀態與副作用次數一致，checkpoint fail-closed |
| Schema／Reader | 舊 V1、新版 Compact／Full 可讀；混合版本 Root／Child Retry、OutcomeUnknown 與 hash guard 正常 |
| Compact 可診斷性 | Phase、可靠性、關鍵錯誤／歧義可追溯，不依賴每輪重複的全域 Views |
| Full 可診斷性 | 詳細 Views／Errors 可用，若有預算限制必須明確呈現截斷及保留範圍 |
| 效能與容量 | 在相同 fixture 下量測 Report bytes、checkpoint P50/P95、累計寫入與峰值記憶體；是否要求 Compact ≤300,000 bytes 依 FR-6 的基線再確立 |
| 舊測試完整性 | 既有 unit tests 不可削弱；若 V1 writer 斷言需因有意版本變更而調整，先證明理由並保留對 V1 Reader 的回歸覆蓋 |

**決策記錄：**本 FR 從 FR-6 原先「立即導入 Compact V2」設計意圖拆出。它是**未來期望功能**，不是已提供的 CLI 行為或當前部署承諾；FR-6 保持 Evidence-First、不先做 Schema Migration。
