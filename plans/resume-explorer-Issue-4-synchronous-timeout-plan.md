# Issue-4 — 同步 COM/UIA 操作超時：詳細調查與修復計畫

- 初稿：2026-11-01；本版更新：2026-11-02
- 優先級：P1（見 `Backlog.md` Issue-4）
- 狀態：**計畫已細化；RCA／修復／實機驗收均未完成**
- 範圍：先調查、再做最小修復；不因撰寫本計畫而修改 Restore 程式碼或執行破壞性操作
- 來源 Report：`02e5f26b61da4a1ba503bea37d15323f.json`（可能包含真實使用者路徑，**不得提交公開 repo**）

## 1. 問題定義與目前證據

既有 Restore 案例有 18 items：13 `Verified`、1 `OutcomeUnknown / NavigationTimeout`、4 `NotAttempted`。異常為 Group 6 / Tab 3（其後 4 items 未嘗試），該項已嘗試 Invoke 與 Navigate，`ElapsedMs=28545`。Navigation 只有一筆 observation，其 `ElapsedMs` 標記約 15,813 ms，`RawCount=68`、`UniqueCount=68`、`Reliable=True`。View 清單包含目標路徑，但不代表「目標 candidate identity 持續穩定 600 ms」已成立。此 `ElapsedMs` 是 Observation 相對階段起點的時間標籤，**不是單次 Observe 執行時間**；不能據此宣稱某次 COM 呼叫卡了 15.8 秒。

同份 Report 為 **3,002,321 bytes**（約 3.00 MB / 2.86 MiB），18 items、**83** 筆 `Diagnostics.Samples`，累積儲存 **5,115** 筆 Views（2026-11-02 逐 Item 唯讀複核；先前 87／5,119 為錯誤計數）。FR-6 已唯讀量測：僅在記憶體中清空診斷 Sample 的 Views 並重新序列化，Report 約為 **116,701 bytes**（原檔 3,002,321 bytes）；重複的全域 Views 為容量主因。**實際 checkpoint 序列化／磁碟寫入時間，以及其是否導致本 Issue timeout，仍未量測／證實。** `RawCount=68` 是全域 Shell 枚舉數量，**不表示某個視窗內有 68 Tabs**。

目前只能確定：`while (Now < deadline)` 限制的是**進入下一輪輪詢的時機**，不能搶佔或取消已進入的同步 Shell COM／UIA 呼叫。造成超時的實際熱點可能是單一 Property、全域列舉、Fingerprint、Explorer／VDI 自身反應、UIA、Checkpoint／JSON，或多項因素疊加；滑鼠焦點尚無因果證據。

### 成功目標與非目標

1. 具體定位慢呼叫所在 `Phase`、`Stage`、單次耗時與 Deadline Overrun；將「一次長阻塞」與「多次短輪詢」分開。
2. 讓 **Deadline correctness** 明確一致：呼叫跨過期限才返回時，不能誤報期限內穩定驗證成功；但不宣稱能硬性中止同步呼叫。
3. 根據數據減少不必要的觀測／重複讀取，不犧牲 Tab identity、完整性、checkpoint 與單次副作用。
4. 如同步阻塞仍不可接受，再評估 Parent/Worker 的有界等待設計。
5. **非目標**：直接調大 10 秒 Timeout 當作根因修復、全面重寫 Restore、為改善成功率跳過歧義檢查，或更動 Issue-3／FR-1 的 Focus／可見性行為。

## 2. 程式碼對照與風險盤點

| 位置 | 目前行為 | 調查焦點 |
| --- | --- | --- |
| `Get-ExplorerObservation()` | `Shell.Application.Windows()` 全域列舉；逐 View 讀 `FullName`、`HWND`、Fingerprint、Identity、`Document.Folder.Self.Path` | Windows() 取得與實際迭代分別耗時；哪個 Property 最慢；有多少 View |
| `Get-WindowFingerprint()` | Windows API + `Get-Process`／StartTime／SessionId；可對同 PID 重複讀取 | 每輪呼叫次數、成本與 PID 一致性 |
| `Get-TabIdentity()` | `Marshal.GetIUnknownForObject` 取得 Identity，隨後 Release | 單次耗時、跨 Observation 穩定性；不可當跨 Process／重啟持久 ID |
| `Add-ObservationDiagnostic()` | 每次 Sample 複製完整 Views／Path／Fingerprint／Errors | FR-6 量測容量／checkpoint 成本；若需調整持久化投影，由 FR-9 評估 |
| `Wait-StableTabBaseline()` | 3 秒期限、3 次可靠觀測且跨 600 ms | **潛在邊界問題**：Observe 在期限內開始、期限後返回，仍可能回傳 `Stable` |
| `Wait-NewExplorerWindow()` | 固定 12 秒輪詢、RootHwnd 去重 | 同步 Observe 可能跨期限；候選歧義處理 |
| `Wait-NewTabCandidate()` | 15 秒偵測、600 ms 穩定、讀取錯誤 200/400/800 ms backoff | Observe／Fingerprint 跨期限；不得重複 Invoke |
| `Wait-TabNavigation()` | 10 秒內連續可靠觀測目標 candidate 的 Path | Path 出現一次不足以 Verified；跨期限的 Observe 必須計時 |
| `Get-NewTabInvokePattern()` | UIA `FindFirst`、`GetCurrentPattern` 同步，無獨立期限 | UIA 熱點、操作前條件與 Focus 變因 |
| `Invoke-TabTransaction()` | Baseline → PrepareInvoke → BeforeInvoke Observe → checkpoint → Invoke → Detect → BeforeNavigate Observe → checkpoint → Navigate → Verify | **沒有 end-to-end 硬性 Deadline**；PrepareInvoke／BeforeInvoke／BeforeNavigate／Invoke／Navigate／Checkpoint 各有阻塞風險 |
| `Write-RestoreCheckpoint()` | `ConvertTo-Json -Depth 32`，暫存檔 + 原子置換 | JSON 生成、磁碟延遲及頻繁寫入的實際成本 |

需先用 deterministic test 證明 Baseline 邊界問題，**不可僅憑程式碼審查就把它列作已發生根因**。現有 `Wait-NewTabCandidate`／`Wait-TabNavigation` 已在成功分支檢查 deadline；不要為統一實作而退化其保障。

## 3. Phase 0 — 安全基線與重現

1. 保存本 Issue 相關程式碼版本、OS／PowerShell／VDI 資訊與 Restore 設定；只分析**經去識別化**的 Report 摘要。原始 Report 不加進 repo。
2. 先跑現有 `tests/Issue2.Tests.ps1`、`tests/RestoreSummary.Tests.ps1` 的無 Explorer／Mock 測試，保留結果當回歸基線（測試須確認不觸及真實桌面）。
3. 建立模擬慢 `Observe`／慢 `Fingerprint`／慢 `Checkpoint` 的 fake-clock fixtures；先讓問題可重現，避免為取得數據在日常 VDI 執行 Restore 壓測。
4. 若確實需要真實高負載，使用獨立且可重設的互動式 Windows VM。先採唯讀觀察；**不得**在工作中的桌面殺 `explorer.exe`、清理未知 Process、關閉既有視窗或覆寫 Snapshot。
5. 建立 `Baseline` 報告：全程耗時、各 Phase 的實際耗時、成功／失敗 ReasonCode、CPU／I/O／Explorer 是否無回應。比較需使用相同 Snapshot、View 數、系統負載條件；無可控重現時註明限制。

**交付物**：可重現 fixture、原版本基線結果，以及不含敏感路徑的測試資料。

## 4. Phase 1 — 儀表化與 RCA（首要工作）

### 4.1 計時邊界

建議沿用既有 `New-ExplorerAdapter().Now` 的單調計時／fake clock 以實作 Deadline 語意，生產環境以 `Stopwatch` 量測同步呼叫耗時；`DateTime.UtcNow` 只供人類閱讀、不能做 Deadline 計算。每次同步呼叫均記錄 **開始前、返回後**，而非只在 `Add-ObservationDiagnostic()` 寫入一個相對時間標記。

- 每次 Observe 記錄：`Phase`、`ObserveStartedAtUtc`（可選）、`ObserveDurationMs`、`DeadlineRemainingBeforeMs`、`DeadlineRemainingAfterMs`、`DeadlineOverrunMs`、`StartedAfterDeadline`、`RawCount`、`UniqueCount`、`IdentitySetReliable`、`ReadErrorCount`。
- 將 Shell `Windows()` **取得集合**、`foreach` 的迭代與逐 View 屬性讀取分開。追蹤 `FullName`、`HWND`、`Get-WindowFingerprint`、`Get-TabIdentity`、`Path` 的 Count／Total／Max；記錄最多 N 個最慢 Stage（預設不保存完整 Path）。
- 其他邊界：`Test-TargetWindow`、`PrepareInvoke`（含 UIA FindFirst／GetCurrentPattern）、`Invoke`、`Navigate2`、`Add-ObservationDiagnostic`、`ConvertTo-Json`、checkpoint 磁碟寫入、Window Creation。
- 跨 Phase 報告 `Item.ElapsedMs` 與各段分解；若計時存在未覆蓋區間，標註 `UnattributedMs`，避免錯把全部差額歸於 COM。
- 對同步例外記 `Stage`、HRESULT、是否已知 HWND、可靠性與 Deadline；不得因 Instrumentation 重新讀取可能阻塞的 COM Property。

### 4.2 診斷資料格式

建議以**選用、向後相容**欄位擴充現有 `Diagnostics`，必要時保存有限的 `TimingSummary`、`SlowStages`、`DeadlineOverrunMs`。先維持目前 V1 Report 與 `ReasonCode` Reader；**不因 Issue-4 儀表化而預先要求 Compact/Full**。若實證需要改變持久化投影或 breaking schema migration，由 **FR-9** 負責設計與相容性；容量、checkpoint 成本證據由 **FR-6** 蒐集。

診斷格式、File I/O 不得在正常 Restore 中持續儲存每輪完整 View 快照。新增儀表化本身須量測 overhead（有／無 Instrumentation 對照），且不能改變 `IdentitySetReliable`／候選驗證的判斷結果。

### 4.3 假設與測試矩陣

| 假設 | 控制變因／實驗 | 判斷依據 |
| --- | --- | --- |
| H1：全域列舉呈規模性變慢 | 20 / 50 / 100+ 全域 Shell Views；單視窗多 Tabs vs 多視窗 | Observe P50／P95／Max、每 View Stage 時間 |
| H2：單個 COM Property 非常慢 | 注入單筆慢 Path／Identity／HWND；隔離 VM 實測 | Max Stage、Deadline Overrun、可靠性 |
| H3：Fingerprint 重複查 PID | 計數同次 Observation `Get-Process`／StartTime | 呼叫次數及可節省時間 |
| H4：Checkpoint／報告成本過高 | 分離 `ConvertTo-Json`、Array 複製、File I/O | Item 耗時占比與 Report 大小 |
| H5：Explorer／VDI 自身卡頓 | 不執行 Restore 的唯讀觀察對照；CPU／記憶體／I/O／App Hang | 卡頓是否獨立存在，不將相關當因果 |
| H6：焦點改變影響 UIA／觀測 | 無互動 vs 切 Chrome／其他 Explorer／目標 Tab | 同條件下失敗原因與身份變化，Issue-3 專案分工 |
| H7：UIA PrepareInvoke 慢 | 分段 UIA FindFirst／GetCurrentPattern | 是否在 Invoke 前已耗費異常時間 |

**Phase 1 Gate**：對至少一個可重現慢案例，能具體回答「耗時在哪個 Stage、每次呼叫多久、何時跨 Deadline、Invoke/Navigate 是否已嘗試、是否存在異常 Checkpoint 成本」。若無法重現，保留證據不足結論並先交付儀表化，不能宣稱 RCA 已完成。

## 5. Phase 2 — 最小風險正確性修復與效能優化

### 5.1 Deadline correctness（優先）

先寫 Test：`Wait-StableTabBaseline` 的第 3 次可信 Observe 在 Deadline 內開始、**跨越 Deadline 後**才返回，不得回報 `Stable`。修復時在可能阻塞的同步操作返回後重新檢查 Deadline，再決定是否允許 Stable／Verified；操作開始前若已逾期則不執行。其他 Wait 函式同步執行此邊界檢查審核。

- 在**副作用前**超時：`PreconditionFailed` 或既有相容 ReasonCode，禁止 Invoke／Navigate。
- 已標記 `InvokeAttempted`、`NavigateAttempted` 或 `WindowCreateAttempted`：若狀態仍無法安全確認，維持 `OutcomeUnknown`，不可因 Deadline 超時自動重送。
- 現有的 600 ms 連續穩定、至少 3 次可靠 Baseline、candidate identity 唯一性、歷史 `Seen` 不忘記歧義、同一 candidate 的 Path 驗證都必須保留。
- 需要新 ReasonCode 時先確認 `Read-RunReport`、Retry Preview／Retry、報告摘要的向後相容性；不得把 `Completed` 誤當所有 items `Verified`。

**不宣稱**本修復能停止已卡住的同步呼叫，也不只把 `NavigationTimeoutSeconds` 加長以掩蓋問題。

### 5.2 依證據優化 Observe

1. 若 Fingerprint 查詢明顯占比高：研究**僅限單次 Observation** 的 PID／Process StartTime／Session 快取；Window Handle、PID 重用、Process 替換等情況仍要保守驗證，不跨次無條件沿用。
2. 若 Path Property 為瓶頸：研究 target-aware 兩階段讀取，先建立**足夠完整**的 HWND／Identity 集合與 duplicate／reliability 檢查，再只對必要 View 讀 Path；目標視窗所有 baseline／new candidates 必須完整可判別。任何無法確立完整性的結果都不得標為 Reliable。
3. 區分需要全域 Path 的 `Capture`／`Wait-NewExplorerWindow`，與可能只需目標 candidate Path 的 Detection／Navigation；不得貿然將所有模式變成只看目標。
4. 若主要成本在診斷／checkpoint：先將實測成本交給 FR-6；若需減少重複 View 快照並引入 Compact/Full，與 FR-9 協調 Report Schema 與向後相容性，始終維持「副作用前原子持久化」語意。
5. 若 UIA 或焦點是瓶頸：先做 Issue-3 的焦點矩陣，再評估安全的 UIA 查找方式；避免使用 SendKeys／滑鼠座標替代安全 identity。

**Phase 2 Gate**：正確性測試全部通過；對同條件基準比較耗時、Observation 數量、Checkpoint 成本及失敗類型；任何優化若降低 identity 完整性或引入重複副作用，必須拒絕／回退。

## 6. Phase 3 — 有界等待的 Worker Isolation（條件性 Spike）

只有 Phase 1/2 已證實「個別同步 COM／UIA call 可能長時間不可控阻塞」，且目前成本不可接受時，才開獨立 Spike；**不應預先承諾此方案必須導入**。

研究 Parent Restore Controller + 獨立 Worker Process：Controller 管 Deadline、Run State、Checkpoint 協定與 IPC；Worker 在單一受控生命週期內完成相關 COM／UIA 操作。優先評估以**完整 Tab Transaction** 為隔離單位，避免每次 Observe 重新產生 Process、遺失候選 Identity 或跨 Process 傳遞不可移植的 COM Reference。

必須在 Spike 解決：Shell COM 與 UI Automation 的 Apartment Model（STA／MTA、Message Pump、Thread Affinity；不得假設一個 STA Runspace 通用）、`IUnknown`／RCW Identity 的生命週期、Windows Session／Desktop 權限、Worker 啟停、Heartbeat、IPC 資料型別、Checkpoint 持久化所有權、Worker 異常退出與孤立 Worker 管理。

**Timeout 安全協定**：

1. Parent 在可重複副作用前，必須確認持久化的 `Attempted` 記錄；在不確定資料已落盤時不可送出副作用。
2. Worker 已發出 `Invoke`／`Navigate` 後卡住、崩潰或遲回，Parent 必須保留 `OutcomeUnknown`／足夠的操作嘗試資訊，不可自動重放。
3. 逾時代表「Controller 不再等待／不再執行後續副作用」，**不代表 Explorer 的副作用已取消**。是否能安全終止 Worker Process 須先驗證；不可終止 `explorer.exe`，亦不可使用 `Thread.Abort` 強殺任意 COM Thread。
4. Worker 重新建立後不得重用舊 `IUnknown` identity；任何後續 Retry 必須重新 Preview、重新驗證 Fingerprint 並沿用不確定性保護。

若 Spike 無法維持一致的 Identity／Checkpoint 語意，**拒絕 Phase 3**，保留有界輪詢與可診斷的未知結果；不得以 Hard Timeout SLA 換取重複建立 Tab 的風險。

## 7. 測試策略

### 7.1 Deterministic Unit Tests（首選）

沿用 `tests/Issue2.Tests.ps1` 的 Adapter + fake clock、無 Pester／無真實 Explorer 依賴。新增 `tests/Issue4.Timeout.Tests.ps1`（或依現有 Test Runner 慣例合併），並納入原有回歸測試。

| 測試案例 | 必須滿足 |
| --- | --- |
| Observe 在 10s Deadline 前進入、16s 才返回 | 記錄約 6s Overrun；不能回報期限內 Verified |
| 第 3 次 Baseline sample 跨期限才返回 | 不得回傳 `Stable`；Invoke = 0 |
| Detection 同步 Observe 長時間阻塞 | Invoke 最多 1、Navigate = 0；結果保守 |
| Navigation 第一次看到正確 Path，但未滿 600ms | `OutcomeUnknown / NavigationTimeout`，不假 Verified |
| BeforeInvoke 的觀測不可靠／跨期限 | 不發出 Invoke |
| BeforeNavigate 觀測不可靠／候選更換 | 不發出 Navigate |
| 觀測中 duplicate identity／多 candidate／baseline 消失 | 安全拒絕，無誤導覽 |
| Fingerprint 的 PID／Process StartTime 改變 | 身分不匹配，不採用 stale candidate |
| `Checkpoint` 在 Invoke／Navigate 前失敗 | 對應副作用次數 = 0 |
| 100+ mock views／非目標慢 Property | reliability 與 identity 不被 fast path 弱化 |
| 診斷關閉／開啟／舊 Report | 恢復決策一致、Reader／Summary／Retry 相容 |
| Worker 逾期／Crash／late response（若進入 Phase 3） | 不重送操作、狀態保守、後續有可審核紀錄 |

測試的 Fake Clock 應能讓 `Observe`、`Fingerprint`、`PrepareInvoke`、`Checkpoint` 分別推進時間，覆蓋「開始時未過期、返回時已過期」的情況；不得只測 `Sleep` 時鐘。記錄嘗試次數和 checkpoint 順序，驗證 **single Invoke / single Navigate**。

### 7.2 效能與 E2E

- 隔離 Windows VM：全域 20／50／100+ View、單視窗多 Tabs vs 多視窗、重複 Path、慢 UNC／OneDrive／Shell View、不同 Explorer 負載。
- 焦點條件 A/B/C/D/E 參照 Issue-3：A 只切其他 App、B 切其他 Explorer、C 切目標 active Tab、D 在目標新增／關閉 Tab、E 關閉目標視窗。A/B 不應錯選；C 需實測；D/E 有歧義則保守停止。
- 比較 Phase 0 vs Phase 2：`P50`／`P95`／`Max ObserveDuration`、`DeadlineOverrunMs`、每 item 耗時、Restore Verified 比率、`OutcomeUnknown` 原因、Report bytes、Explorer CPU／I/O。
- CI：GitHub Actions Windows runner 可跑無 GUI deterministic／mock tests；**不可假設** hosted runner 能穩定跑互動式 Explorer E2E。真實 GUI E2E 使用專門互動桌面且可重設的 VM。
- 禁止在主要工作 VDI 執行可能改動大量 Tabs／Windows 的壓測；未經審核不可殺 Explorer、未知 Process 或清除既有使用者視窗。

## 8. Acceptance Criteria 與決策門檻

### Correctness

- 每次 Observe 有可核對的 start/end duration、Phase、主要慢 Stage 和 Deadline overrun；一次長同步呼叫不再被誤判為多次 polling。
- 任何返回時已跨期限的觀測不得**單憑該次結果**錯誤回報期限內 Stable／Verified；同時不誤宣稱同步 COM 呼叫已被取消。
- 保留 3 次可靠 Baseline、600ms 連續穩定、單一候選、完整 identity／fingerprint 檢查。
- Status／ReasonCode／`Completed`、原始 Group/Item 索引及舊 Report 讀取與既有行為相容。

### Safety

- 每筆 transaction 的 `Invoke` 最多一次、`Navigate` 最多一次；副作用之前的 atomic checkpoint 必須成功；不因慢呼叫而自動重送。
- 歧義、全域觀測不完整、已嘗試副作用後未知結果均 Fail Closed；`PreviewRetry`／`Retry` 仍需顯式處理不確定性。
- 不新增 `-WindowStyle Hidden` regression、不將 Focus 變更當成選 Tab 依據、不影響現有 Explorer／使用者未儲存工作。

### Performance

- 量化同條件調整前後的 Observation／Item 延遲、Overrun、Report I/O 與成功率；設定改善目標須在 Phase 1 Baseline 後決定。
- Phase 2 不承諾 Windows COM 不合作時的硬性 wall-clock SLA。若需硬性 Controller 等待上限，必須另驗證 Phase 3 的隔離與不重送協定。
- 應能在高 View 數、慢 VDI、焦點切換條件下保持身份安全；效能結果不能以犧牲保護換取。

## 9. 建議工作分解與 Commit 順序

| 順序 | 工作／建議 Commit 範圍 | 依賴 | 交付物 |
| --- | --- | --- | --- |
| 1 | `test(issue4): add delayed-observe and deadline boundary fixtures` | 無 | Baseline／Navigation／Checkpoint fake-clock Regression Tests |
| 2 | `feat(issue4): instrument synchronous stages and deadline overrun` | 1 | 可診斷、有限採樣的 Timing／SlowStage 指標 |
| 3 | RCA：重跑測試與分析分段結果（獨立驗證紀錄） | 2 | 熱點歸因、替代假設及 before/after Baseline |
| 4 | `fix(issue4): enforce post-call deadline checks` | 1–3 | Deadline Correctness 修復與回歸測試 |
| 5 | `perf(issue4): optimize proven observation bottleneck` | 3–4 | 依實測選做快取／target-aware 讀取等最小改動 |
| 6 | Unit／Integration／隔離 E2E、數據比較 | 4–5 | 測試結果、Regression 與風險說明 |
| 7 | `spike(issue4): evaluate bounded worker isolation`（如有必要） | 3–6 | 決策記錄、PoC／拒絕理由；不預先合入產品 |
| 8 | 文件收尾：Backlog、README、驗證紀錄 | 驗收後 | 更新狀態與實測限制 |

建議把 **Instrumentation、Deadline Correctness、Performance Optimization** 分別提交，以便單獨 Review、回退與 Git Bisect；RCA 必須有測試或 trace 支持，不能以提升 Timeout 參數取代分析。**本計畫文件更新本身不等於已完成任何階段。**

## 10. 相依 Issue 與明確邊界

- **Issue-2**：必須保留原始 Group/Item 索引、`Seen` 候選歷史、`OutcomeUnknown`、Atomic Checkpoint、Single Invoke／Navigate、`PreviewRetry`／`Retry` 保護；Issue-4 不可為效能弱化這些不變量。
- **Issue-3**：焦點與 UIA active-tab 相依性由 `resume-explorer-Issue-3-focus-independence-plan.md` 專門驗證；Issue-4 僅提供性能指標及協助分辨焦點因果。
- **Feature Request-6**：Report 容量／checkpoint 成本量測及**安全的歷史 Run Family Retention**；現階段不預先承諾 Compact 或 Schema V2。見 `resume-explorer-Feature-Request-6-report-size-plan.md`。
- **Feature Request-9**：當量測顯示必要且需求排程允許時，再評估 Compact 預設、Full opt-in 與新版 Report Schema／Reader 相容性。見 `resume-explorer-Feature-Request-9-diagnostic-level-plan.md`；Issue-4 只提供必要 Timing 證據，不能以縮檔推論 COM Timeout 已修復。
- **Explorer 多 Process／Not Responding 的獨立問題**：優先採唯讀觀測，勿僅依 PID 數量推論 Leak；若慢 Restore 和重啟後卡頓同時存在，仍須分開調查。
