# Resume Explorer — Issue-2 修復計畫

- 日期：2026-11-01
- 更新：依 `Backlog.md:36–44`（commit `f4cc418`）將異常偵測改為預設額外 **3 次 retry（200／400／800 ms）**，並統一 timeout、報告與測試契約。
- 狀態：設計提案；只更新本修復計畫，尚未修改或執行 Restore 程式
- 建議目標版本：`0.1.0-beta.2`，以完成下述驗收為發布條件

## 1. 結論與修復策略

Issue-2 應採用「**一次建立請求，有限次重新觀測，確認新分頁身分後才導覽；無法確認則停止該 Group，保存可補做的結果**」。

不要在整段 `Add-ExplorerTab → Wait-NewTab → Navigate2` 外面包 retry。新增分頁不是可安全重複的操作；偵測逾時或 Invoke 拋出例外，都不一定代表 Explorer 沒有收到請求。

本次設計的三個重點：

1. 建立前取得可信且穩定的 baseline，讓「新分頁」比較有意義。
2. 偵測階段能容忍短暫未曝光、重複列舉與可重試的讀取錯誤，但不以猜測解決真正的多候選。
3. 完整記錄「已確認完成、已操作但結果不明、尚未嘗試」，讓使用者可以指定原 Group 的視窗及需要補做的項目。

**不是所有 `Multiple new tabs detected` 都能靠等待修復。** 本方案改善可恢復的暫時性問題；遇到無法歸因的多個真實候選，仍然保留停止該 Group 的行為。

## 2. 依據、現況與範圍

### 2.1 已核對的專案資料

- 專案：`E:\_projects\tools\scripts\resume-explorer`。
- 讀取：`resume-explorer.ps1`、`Backlog.md`、`README.md`。
- 腳本版本：`0.1.0-beta.1`，151 行。
- 本次核對 HEAD：`f4cc418`（只修改 Backlog，新增 3 次 retry 的預設值）；修改本計畫前 `git status --short` 無輸出。原始計畫曾記錄 `b21adcb`，現已更新基準。
- 相關歷史：`b251913` 新增 Backlog；`669de2a` 更新背景還原需求；`df262e5` 更新 Beta README。
- README 已記錄 Windows 11 Enterprise 23H2 / Build 22631、VMware Horizon VDI 的小規模成功經驗；尚不能視為所有 Windows 版本皆支援。

本次核對現有腳本與 Git 後，**只編輯本 Markdown 修復計畫**；未新增 Explorer 視窗、未重啟 Explorer、未更動任何產品腳本或執行測試。

### 2.2 Issue-2 的原始需求

Backlog 的錯誤：

```text
WARNING: Group 2: Multiple new tabs detected; cannot safely choose one.
Remaining tabs in this group skipped.
```

使用者希望：暫時性問題可 retry 一定次數；仍無法安全選擇分頁時，放棄該 Group 剩餘項目並記錄，供後續手動 retry，同時指定要加入該 Group 的分頁。

### 2.3 保留的行為與本次邊界

- 保留 Windows/Tabs 分組，不把每個分頁改開成獨立視窗。
- Restore 只新增；不關閉分頁、不終止 Explorer、不回滾使用者的操作。
- 不使用 SendKeys、Clipboard 或要求輸入 `OPEN`。
- 不在此 Issue 擴大處理 ZIP / Shell namespace 支援（Issue-1）。
- 背景顯示與不搶焦點是 Feature Request-1；本計畫不宣稱解決，也不將該需求縮減為隱藏 Console。
- 不新增 Restart、GUI、PATH 安裝或 Snapshot 歷史功能。
- 測試僅涵蓋此 Issue 需要的觀測、辨識、結果紀錄及補做流程，不順帶全面重構專案。

## 3. 已確認的缺陷與尚未證實的原因

### 3.1 現行流程

| 位置（目前腳本） | 行為 | 影響 |
| --- | --- | --- |
| `Get-ExplorerTabViews` | 列舉 Shell Windows；多個 catch 為空 | 不完整觀測可能被當作完整清單 |
| `Restore-Snapshot` | 建立前只抓一次 Identity 陣列 | 尚未曝光或讀取失敗的既有分頁可能遺漏 |
| `Wait-NewTab` | 200 ms 輪詢、最多 7 秒 | 有基本等待，但沒有多候選 reconciliation |
| `Wait-NewTab` | 一個候選立即 return；多個立即 throw | 單次樣本直接決定成功或失敗 |
| `Navigate2` 後 | 等 350 ms；同 HWND 任一相同 Path 就算找到 | 舊的同路徑分頁可能掩蓋新增分頁未導覽完成 |
| navigation 查核失敗 | 只印 warning 後繼續下一個分頁 | 前一個操作未收斂，便開始下一個操作 |
| Group catch | warning 後 break | 沒有機器可讀的已完成／不明／未嘗試清單 |

**現有程式沒有自動重複 AddButton 的 retry。** 重複建立是必須避免的新修復風險，不應寫成已證實的現行根因。

### 3.2 根因假說與驗證方式

| 假說 | 為何值得查 | 需要的證據 |
| --- | --- | --- |
| baseline 不完整 | 只有一次列舉且會吞掉例外 | Invoke 前多輪 Identity 集合、列舉錯誤及遺漏項目 |
| Shell COM 曝光延遲 | 視窗剛建立或前一分頁仍在導覽 | 各 Identity 首次出現時間及路徑變化 |
| 同一物件被重複列舉 | 現行以列數判斷多候選 | 多列是否有相同 COM Identity |
| 使用者或另一腳本同時開分頁 | 兩個真實新分頁會造成歧義 | 完整候選歷史、UIA tab 數、同時操作紀錄 |
| COM 導覽物件被替換 | 物件生命週期未必等同視覺分頁生命週期 | 未新增分頁時，舊 Identity 是否消失而新 Identity 出現 |
| Shell HWND 與頂層 HWND 關係不一致 | AddButton 已轉成 GA_ROOT，但偵測仍用原始 HWND | RawHwnd、RootHwnd、PID 及實際分組關係 |

目前只有 Backlog 的錯誤訊息，**無法斷定是哪個假說造成 Group 2 失敗**。先加入觀測資料，再依重現結果判斷；不要把「延遲」或「Identity 不穩」直接當 RCA 結論。

### 3.3 API 契約與適用限制

Microsoft 的 COM identity 規則保證同一物件的 `IUnknown` identity；不保證 Windows 11 的同一視覺分頁在整個生命週期一定對應同一 COM 物件。[1]

`GetIUnknownForObject()` 取得的指標增加參考計數，必須對稱 Release；現有 `try/finally` 的配對應保留。[2] 不應為了修 Issue-2，直接刪掉 Release 或用 `FinalReleaseComObject()` 強制釋放可能共享的 RCW。

UI Automation Invoke 是動作請求，不能把呼叫返回當成分頁已建立或已可透過 Shell COM 觀測。[3] 文件也提醒 provider 可能出現阻塞情況，因此輪詢 deadline 不等於可強制中斷任意卡住的 COM/UIA 呼叫。

以上文件沒有提供 Windows 11 Explorer 的交易 ID 或「這次 Invoke 建立哪個分頁」的正式關聯 API。本設計仍依賴目標環境已驗證的行為；穩定取樣能降低競態，但不能證明完全沒有外部操作。

## 4. 必須維持的不變條件

1. **每個自動補建交易最多呼叫一次 Invoke**；進入 Invoke 前就標記 `InvokeAttempted=true`。
2. Observe retry 不呼叫 AddButton，也不重新發送 Navigate2。
3. 同一 Group 一次只有一個未完成交易；前一個未驗證成功就不開始下一個。
4. 候選比對只能使用 Invoke 前凍結的 baseline；不能把 Invoke 後未知候選補入 baseline 來消除歧義。
5. Path 不是分頁 ID；相同路徑可以合法存在多次。
6. 真實的多候選歷史不能因下一輪只剩一個而被清除。
7. 不選第一個、最後一個、作用中分頁，亦不以 Home / 空路徑猜測誰是新分頁。
8. 操作目標不明時，`Navigate2` 呼叫次數必須為零。
9. 停止一個 Group 後，其他 Group 在正常環境下仍可繼續；若是全域 Shell 不可用或紀錄寫入失敗，則停止整次 Restore。
10. HWND 與 COM Identity 都不可作為跨程序、跨登入或跨重啟的持久唯一 ID。

## 5. 建議架構與函式責任

保持小型 PowerShell 工具；可抽出一個內部 core 檔案以供 Pester 載入，但不要為此建立完整框架。若保留單檔，需有不執行 Action dispatch 的安全測試入口。

| 函式／元件（提議名稱） | 責任 |
| --- | --- |
| `Get-ExplorerObservation` | 傳回 Views、讀取錯誤、完整性判斷與時間；不新增分頁 |
| `Get-WindowFingerprint` | 解析 Raw/Root HWND、PID、程序建立時間及視窗存活狀態 |
| `Wait-StableTabBaseline` | 取得穩定基準與既有 COM 物件參考 |
| `Invoke-NewTabOnce` | 尋找 AddButton、標記 invoke 邊界、呼叫一次 |
| `Resolve-NewTabCandidate` | 純邏輯：baseline + 觀測歷史 → pending / unique / ambiguous / invalid |
| `Wait-NewTabCandidate` | 有界輪詢與錯誤分類；不做任何建立動作 |
| `Wait-TabNavigation` | 在已識別的同一候選上等待目標路徑可確認 |
| `Write-RestoreCheckpoint` | 原子更新結果檔及恢復狀態 |
| `Restore-Group` | 串接一個 Group，失敗後標記其餘項目 |
| `Retry-GroupItems` | 讀取報告、驗證使用者指定目標、執行選定未完成項目 |

所有輪詢共用 clock / sleep / observation adapter，測試時注入資料序列，不必真的操作 Explorer。

## 6. 詳細演算法

### 6.1 觀測完整性與 Identity

`Get-ExplorerObservation` 不再只回傳一個陣列：

```text
ObservedAtUtc, ElapsedMs
Views[]: RawHwnd, RootHwnd, PID, Identity, Path, PathReadable, ComObject
EnumerationSucceeded, IdentitySetReliable
ReadErrors[]: Stage, HResult, Message, KnownHwnd
```

- 已確認是非 Explorer 項目可略過；讀不到 FullName / HWND / Identity 的未知項目，不能默認與目標無關。
- 目標分頁的 Path 暫時讀不到，不等於身分清單不完整。保留該 Identity，標記 Path 不可讀；辨識與導覽驗證分開處理。
- 相同 Identity 的重複列可去重，但若同 Identity 出現互相矛盾的視窗資料，將該輪標為不可信。
- 原始多列數、去重後數量都保留在診斷資料，避免去重掩蓋來源問題。
- 交易期間保留 baseline 及已見候選的 RCW 參考，避免只留指標字串卻丟失物件生命週期脈絡；交易結束後解除參考，避免累積。
- 不序列化 ComObject；只將身分字串寫入診斷資料，且明確標示僅供該次 run 判讀。

### 6.2 建立前的 baseline

1. 確認目標視窗存活，且仍屬於預期 Explorer 程序。
2. 取得連續可信觀測；至少三輪相同 identity 集合，跨越約 600 ms 的安定期。
3. 若 baseline 期間有變化，重新計算穩定期；整體最長約 3 秒。
4. baseline 若持續不穩定或包含無法排除的列舉錯誤，返回 `BaselineUnstable`；**不 Invoke**。
5. 凍結 baseline identity 集合及參考。Invoke 前再檢查視窗指紋未變。

這裡的「可信」是指沒有已知列舉錯誤且符合已測試環境的分組模型，並非數學上證明已列出所有可見分頁。若實測 Shell COM 經常漏掉實際分頁，應把該環境列為不支援，或先完成可靠的 UIA／COM 關聯方案。

UIA tab 數可作診斷交叉核對；只有實測確認它對應的是目前視窗全部 Tabs 時，才可升格為建立前的必要條件。不可直接假設所有後代 `TabItem` 都是 Explorer 分頁。

### 6.3 Invoke 與例外分類

- 找不到 AddButton、取得不到 InvokePattern：尚未進入 Invoke，可有限次重新找控制項；每次仍受 baseline 與 deadline 約束。
- 預設在穩定 baseline 後只查找並呼叫一次；不要讓控制項重試與觀測 retry 形成巢狀無界迴圈。
- 進入 Invoke 前先持久化 `InvokeAttempted`。即使 crash 發生在紀錄後、實際呼叫前，後續也採保守的「可能已執行」。
- Invoke 拋出例外：記錄 HResult，進入只讀 reconciliation；不可直接再 Invoke。
- 對無法判定是否已執行的 Invoke 例外，本版即使觀察到一個候選，也先以 `InvokeOutcomeUnknown` 停止，不自動導覽；除非後續實測能建立更強的歸因依據。

### 6.4 偵測重試與 reconciliation

依 Backlog 新增的預設值，明確採用 **首次觀測 + 最多 3 次「只讀重新觀測」**，重試間隔為 **200 / 400 / 800 ms**。這不是 3 次 AddButton，也不是 3 次重新 Navigate，更不是重跑整個 Group。

建議初始設定（待實測調整；下列屬**待實作**介面，不是 beta.1 已有參數）：

| 參數 | 預設 | 意義 |
| --- | --- | --- |
| `PollIntervalMs` | 200 | 尚未發現候選時的正常輪詢週期；不消耗異常 retry 額度 |
| `DetectWindowSeconds` | 7 | 從本次 Invoke 邊界起算的**單一**偵測總預算，含所有 poll / retry / sleep |
| `MaxRetries` | 3 | 異常觀測後允許的額外重新觀測次數；首次觀測不計，最多 4 個該異常序列樣本 |
| `RetryDelayMs` | `@(200, 400, 800)` | 第 1／2／3 次額外觀測前的退避間隔；預設總額外等待 1,400 ms |
| `StableDurationMs` | 600 | 同一候選與可信完整集合需維持穩定 |
| `NavigationTimeoutSeconds` | 10 | 導覽結果等待上限，與偵測 retry 分開 |
| `BaselineTimeoutSeconds` | 3 | Invoke 前 baseline 安定期上限，與偵測 retry 分開 |

設定示意：

```powershell
# 待實作：可作為 Restore 的可調參數／內部設定
[int]$MaxRetries = 3
[int[]]$RetryDelayMs = @(200, 400, 800)
```

**重試的精確語義：**

1. **正常等待不等於 retry：**沒有新候選時依 `PollIntervalMs` 輪詢，直到出現可信候選或達到 7 秒總期限；不能因 `MaxRetries=3` 就只檢查 4 次後放棄。
2. **異常重新觀測才計數：**遇到單次讀取錯誤、暫時無法確認觀測完整性或多候選疑義時，只重新取得 Shell COM/UIA 的觀測快照。第 1／2／3 次額外觀測分別延後 200／400／800 ms；絕不再次呼叫 `Add-ExplorerTab`／`Invoke()`／`Navigate2()`。
3. **不要重複睡眠：**異常 retry 的 backoff 取代該次正常 poll sleep，不能同時 sleep 200 ms 再 sleep 200／400／800 ms；異常解除後才回到一般 polling／穩定性確認。
4. **總期限優先：**以單一 `Stopwatch`／deadline 涵蓋正常輪詢與異常 retry；剩餘時間不足時提前停止，不為了湊滿 3 次而超時，也不因每次 retry 重設 7 秒。
5. **Config 可調且受限制：**`MaxRetries` 建議限制在 0–5；`RetryDelayMs` 必須是非空、正整數毫秒陣列。第 N 次使用第 N 個值，超出陣列長度時沿用最後值；`MaxRetries=0` 僅停用異常額外觀測，不停用 7 秒內正常輪詢。無效設定須在任何 Explorer 副作用之前拒絕。
6. **觀測與結論分離：**同一 Identity 的多筆列舉先去重（不必消耗 retry）。若曾見 A、B 兩個不同的新 Identity，後來只見 A 仍不可認定 A 就是本次 Invoke 建立的分頁；3 次 retry 只能幫助診斷，**不會消除真實歧義**。已確定不可恢復者可提早保守停止。
7. **適用範圍：**此 `MaxRetries` 僅控制 Invoke 後的異常偵測；不控制建立前的 AddButton 查找、baseline、導覽驗證或 `-Action Retry`（使用者指定項目補做），避免把兩種 retry 混為一談。

上述時間是輪詢邏輯的預算，不保證能中斷卡住的同步 COM/UIA 呼叫；計畫中不得宣稱整次 Restore 的嚴格 wall-clock 上限。

每輪執行：

1. 取得 fresh observation，驗證視窗指紋。
2. 如本輪有讀取錯誤，記錄並中斷穩定計時，不用它證明候選消失或成功。
3. 去重後取 `current identities − baseline identities`。
4. 把所有看過的不同候選加入 `SeenCandidateIds`，保存首次／最後看見時間與樣本。
5. 檢查 baseline 的原有身分是否仍完整。既有身分消失或換成新身分，先標記環境變動，不能把替換物件當成新增分頁。
6. 依下表決定繼續等待或停止。

| 觀測 | 決策 |
| --- | --- |
| 零候選 | 只等待；逾時為 `NoCandidateObserved`，不自動補點 |
| 同一候選重複多列 | 相同 Identity 去重；若其餘條件成立，可進入穩定驗證 |
| 一個候選、baseline 完整、整段歷史只有該候選 | 維持安定期後才可選定 |
| 某輪曾有 A/B 兩個不同候選，後來只剩 A | 仍是歧義；B 消失不是 A 正確的證據 |
| 從 A 變成 B，即使每輪都只有一個 | 候選身分不穩，禁止導覽 |
| baseline 成員消失後再出現 | 視為環境變動；本版保守停止，避免漏判關閉／重建 |
| 視窗關閉、程序換代或 root 不符 | 立即中止該 Group |

對持續歧義可等到觀測預算結束以補充證據，但不要期待多等幾秒就能證明歸屬。若已確定是不可恢復的目標消失，立即返回，不消耗全部重試次數。

**本版不採用啟發式候選排名。** UIA selected tab、RuntimeId、Path、左右位置皆不能單獨建立與 COM 物件的可靠映射。如果診斷證明問題需要跨模型映射才能解決，應另開有明確驗收的設計，不在本修復中偷偷猜選。

### 6.5 導覽及完成判定

1. 選定候選後，再取得一次可信觀測，確認該候選仍唯一、baseline 完整、目標視窗未變。
2. 使用該候選的有效 COM 參考，對指定 Path 呼叫一次 `Navigate2()`。
3. 進入 `Wait-TabNavigation`，讀取同一 Identity 的路徑；不要用 Group 內任意分頁的相同 Path 代替。
4. 對已支援的檔案系統路徑，使用集中定義的比較規則：大小寫不敏感，妥善處理結尾分隔符，保留磁碟根目錄及 UNC 結構。不以過度正規化將不同路徑合併。
5. 同一候選連續可信觀測到目標路徑，且沒有身分／視窗異常，才標記 `Verified`，再開始下一項。
6. Navigate2 例外、候選消失、身分替換或逾時，標記結果不明並停止該 Group；不再送一次 Navigate2，也不新增替代分頁。

此處 `Verified` 定義為「該候選身分的 Shell 路徑已觀測為目標」，不宣稱資料夾內容已全部載入。網路慢速、DFS、reparse point 等路徑等價問題先列為限制；不能因舊分頁已開著同路徑就判定成功。

### 6.6 主要流程偽碼

```text
for each group:
    identify the newly created target window without guessing
    for each original snapshot item in order:
        checkpoint item state
        baseline = wait for reliable stable baseline
        if baseline unavailable: stop group before Invoke

        checkpoint InvokeAttempted
        invoke AddButton at most once
        start one 7-second detection deadline (never reset on retry)
        retryUsed = 0
        while detection deadline not reached:
            observe with frozen baseline; preserve every seen candidate ID
            if no candidate and observation is reliable:
                sleep normal poll interval (200 ms); continue
            if one attributable candidate is reliable and stable for 600 ms:
                break with candidate
            if identity/history proves irrecoverable ambiguity:
                break with OutcomeUnknown (do not guess)
            if observation is transiently unreliable and retryUsed < MaxRetries:
                delay = RetryDelayMs[min(retryUsed, RetryDelayMs.Length - 1)]
                sleep at most the remaining deadline; retryUsed += 1
                continue
            break with OutcomeUnknown (retry exhausted or deadline)
        checkpoint RetryAttemptsUsed and actual detection duration
        if invocation outcome or candidate attribution is uncertain:
            checkpoint current item as OutcomeUnknown
            mark later items NotAttempted
            stop group

        revalidate unique candidate
        checkpoint NavigateAttempted
        navigate that candidate at most once
        wait for that identity to expose expected path
        if not verified: checkpoint and stop group
        checkpoint Verified
    continue with next group when global environment is healthy
write final summary
```

## 7. Group 視窗識別的必要防線

現有 `Wait-NewExplorerWindow` 遇到多個符合路徑的新 HWND 時直接取第一個。若 Group 從一開始就綁錯視窗，再完善的分頁 retry 也會在錯誤 Group 操作。

本 Issue 至少補上：

- 新視窗候選使用去重後的視窗集合，不能把同視窗多個 COM views 算成多個視窗。
- 多個候選不取 `[0]`；有限等待後無法確認，就記錄 `WindowAmbiguous`，不新增後續 Tabs。
- 第一個路徑也納入結果報告；建立新視窗與辨識失敗時，不能把它寫成「完全未嘗試」。
- 診斷先同時記錄 RawHwnd / RootHwnd；是否全面改用 RootHwnd，要以目標環境實測決定。若需要正規化，必須同時套用於建立、偵測、導覽驗證及 retry 目標，不能只改一處。

此項是避免 Issue-2 修復誤操作的必要防線，不擴大到 Capture 格式與所有視窗管理功能。

## 8. 結果報告與後續手動補做

### 8.1 不遺漏目前失敗項目

保留原 Snapshot 的 `GroupIndex`、`ItemIndex`，索引一律從 1 起算。即使過濾無效路徑，也不重新編號。相同 Path 的兩個項目仍是兩個不同要求。

| Status | 定義 | 可否直接自動補做 |
| --- | --- | --- |
| `Verified` | 該項目已通過身分與目標路徑驗證 | 否 |
| `NotAttempted` | 尚未送出建立請求 | 使用者指定後可執行 |
| `PreconditionFailed` | 建立前的條件未成立，沒有 Invoke | 修正條件後可指定執行 |
| `OutcomeUnknown` | 可能已建立／導覽，但無法確認 | 不可默認重做，必須明確選入 |
| `SkippedInvalidPath` | 無效或當下不可存取 | 先修正或重新檢查路徑 |

`ReasonCode` 與 Status 分開，例如 `AmbiguousCandidates`、`IdentityChanged`、`NavigationTimeout`、`WindowGone`。

報告必須含：當前失敗項目、其後尚未嘗試項目、已完成項目，不能只儲存「remaining paths」。

### 8.2 持久化與欄位

提議結果格式 `SchemaVersion: 1`，另存於使用者本機 application-data 下的 `ResumeExplorer\Runs\<RunId>.json`；可用 `-ReportPath` 覆寫。原始 Snapshot 不修改。

主要欄位：RunId、StartedAtUtc、ToolVersion、SourceSnapshotHash、Snapshot 的選定原始項目、OS/PowerShell 版本、GroupIndex、ItemIndex、RequestedPath、Status、ReasonCode、InvokeAttempted、NavigateAttempted、ElapsedMs、觀測摘要、WindowFingerprint。

每項偵測診斷另記：`MaxRetriesConfigured`、`RetryDelayMsConfigured`、`RetryAttemptsUsed`（僅額外異常觀測，不含正常 poll）、`PollCount`、`DetectionElapsedMs`、`SeenCandidateCount`、`LastObservationError`。若 3 次重試用盡，`ReasonCode` 仍須保留實際原因（例如 `AmbiguousCandidates`／`ObservationIncomplete`），不能只有 `RetryExhausted` 而失去根因資訊；若 7 秒 deadline 先到，亦如實記錄已使用次數。

WindowFingerprint 包含 HWND、RootHwnd、PID、程序建立時間、SessionId，皆僅作驗證提示；不能以報告裡的舊 HWND 自動操作未來的視窗。

- 在有副作用的操作前、每項結果完成後、Group 中止時更新 checkpoint。
- 同目錄暫存檔寫完後原子置換；用 `try/finally` 寫最終狀態。
- 開始前確認報告位置可寫。若中途無法保存，印出最後狀態並停止後續建立，不能默默失去補做依據。
- 每個 run 用新 ID，不覆蓋其他 run。診斷明細可用同 RunId 的 JSONL；正常報告保持精簡。
- 若程序被強制中斷，最後的 Attempted 狀態一律解讀為結果不明，不自動接續。

### 8.3 手動補做介面

以下為**待實作介面示例，現在的 beta.1 尚不支援**：

```powershell
# 只預覽報告中的 Group、項目與現存目標視窗
.\resume-explorer.ps1 -Action PreviewRetry -ReportPath .\run.json

# 把原 Group 2 尚未嘗試的項目，加入明確指定的現存視窗
.\resume-explorer.ps1 -Action Retry -ReportPath .\run.json `
    -GroupIndex 2 -TargetHwnd 123456 -ItemIndexes 4,5

# 使用者檢查畫面後，明確選擇也補做結果不明的第 3 項
.\resume-explorer.ps1 -Action Retry -ReportPath .\run.json `
    -GroupIndex 2 -TargetHwnd 123456 -ItemIndexes 3 `
    -IncludeUncertain
```

`TargetHwnd` 是使用者當次選擇的目標，不自動相信報告中的舊 HWND。執行前列舉並驗證現在的程序／視窗指紋，建立本次 baseline；預覽所示指紋若已改變則拒絕執行。若無法可靠辨識原視窗，由使用者重新明確指定替代視窗，不能自動以相同 Path 猜配。

補做限制：

- 必須指定 Group 與 ItemIndexes；不要自動遍歷全部失敗項目。
- 拒絕重複索引、已 Verified 索引，以及缺少 `IncludeUncertain` 的不明項目。
- 本版補做一律「新增所選項目」，不自行重用或關閉遺留空白分頁。
- UIA／COM 無法可靠定位遺留分頁時，提示使用者自行整理，不能猜選後 Navigate。
- 不以「此 Path 已存在」自動略過；同路徑多分頁是合法情境。
- 新 retry run 關聯 ParentRunId，保留原報告；從來源報告已完成補做的項目需檢查子 run，避免使用者誤重跑。這仍不提供跨 crash 的 exactly-once 保證。
- 使用同一套建立／觀測／驗證 core；不是再維護一份 Restore 邏輯。

這個介面不增加 `OPEN` 等互動確認。對結果不明的項目，以顯式參數表達使用者已檢查並選擇補做。

## 9. 實作順序與可交付成果

### 階段 A：先建立可觀測性並確認假說

1. 加入 observation 結果與錯誤分類，保留現有動作次數。
2. 加入 Raw/Root HWND、Identity、時間序列、Invoke 邊界診斷。
3. 在原問題環境重現 Group 2 型態；記錄 Windows build、PowerShell 版本、分組大小及是否有同時操作。
4. 以資料判斷重複列、baseline 遺漏、身分更換或真正併發；未重現就標為尚未定位，不能宣告 RCA 完成。

交付：可用於判定根因的匿名化 trace，以及採用／排除各假說的說明。

### 階段 B：核心修復

1. 抽出可單元測試的候選判定函式。
2. 實作 stable baseline、Invoke-once 與第 6.4 節的可調 `MaxRetries=3`、`RetryDelayMs=@(200,400,800)`；每次僅重讀觀測、共用原有 7 秒偵測 deadline，正常 polling 不消耗重試額度。
3. 保留候選歷史與可信度；加入多候選／身分變更保守停止。驗證多個不同 Identity 曾出現時，即使重試後剩單一候選也不能直接導航。
4. 實作同一候選的 navigation 驗證。
5. 修正新視窗多候選取第一個的防線。

交付：短暫延遲可恢復，真正歧義不會導向錯誤分頁。

### 階段 C：報告與可補做流程

1. 加入原始索引、狀態、checkpoint 及可讀摘要。
2. 實作 PreviewRetry／Retry 的目標驗證及項目選擇。
3. 記錄子 run，避免直接改寫原始失敗證據。

交付：能完成 Backlog 所要求的「放棄後記錄、指定 Group 與分頁手動 retry」。只完成階段 B 不能將完整 Issue-2 關閉。

### 階段 D：驗收與文件

1. 跑完下列自動化與實機案例。
2. README 說明「首次觀測不算 retry、預設額外 3 次 200／400／800 ms、最多 7 秒偵測總預算」、設定方式、結果狀態、補做命令與已知限制，避免使用者誤以為會再執行 3 次 AddButton。
3. Backlog 保留原始錯誤例，補上根因證據、修復 commit、測試環境與未涵蓋條件。
4. 確認腳本與 README 版本一致，才標記 `0.1.0-beta.2`。

## 10. 測試矩陣

### 10.1 純邏輯／adapter 測試

| 案例 | 模擬序列／條件 | 必須驗證 |
| --- | --- | --- |
| 正常新增 | B → B+A，持續穩定 | Invoke 1 次、Navigate 1 次、Verified |
| 延遲曝光 | 多輪 B，之後 B+A | 只延長偵測，不重新 Invoke |
| 完全逾時 | 永遠 B | Invoke 1 次、Navigate 0 次、OutcomeUnknown |
| 重複列 | B+A+A，相同 Identity | 去重後只選 A；保留原始列數 |
| 真正多候選 | B+A+C | 不 Navigate，Group 停止 |
| 多轉單 | B+A+C → B+A | 不因 C 消失就選 A |
| 單候選換身分 | B+A → B+C | 不把 C 當作 A |
| baseline 遺漏 | Invoke 前列舉錯誤／集合變動 | 不建立，或先完成可信穩定基準 |
| baseline 消失 | B 中某個 ID 消失 | 不導覽任何新候選 |
| 短暫讀取錯誤 | 正常 → 錯誤 → 正常 | 錯誤不視為空集合，穩定計時重來 |
| retry 次數與間隔 | 首次異常 + 3 次仍不可信；fake clock | 額外觀測恰為 3 次，睡眠依序 200/400/800 ms；AddButton 僅 1 次、Navigate 0 次 |
| 第 1／2／3 次恢復 | 每次分別在第 N 次異常重觀測後取得可信唯一候選 | `RetryAttemptsUsed=N`，停止額外 retry，穩定驗證通過後才 Navigate |
| 正常零候選輪詢 | 先連續 N 輪零候選，最後才出現 A | 200 ms 正常 poll 不占用 3 次 retry；7 秒內可繼續等待 |
| 即將到期的 retry | 6.8 秒才遇異常，需 sleep 400/800 ms | 偵測到 7 秒即停止，不能重新展開 7 秒或湊滿 3 次 |
| 調整 retry 設定 | `MaxRetries=0`、`MaxRetries=5`、自訂短陣列、無效負數／空陣列 | 0 停用額外重試但正常 poll 仍有效；超出長度沿用最後延遲；非法值於 Invoke 前拒絕 |
| 多候選經 retry 變單 | 首輪 B+A+C，後續 B+A | `SeenCandidateIds` 保留 A/C；即使重試完仍不可 Navigate |
| Invoke 拋例外 | 例外後候選出現 | 不重點、不自動導覽、結果不明 |
| 同路徑既有分頁 | 舊 tab 已是目標，A 還未導覽完成 | 舊 tab 不可讓 A 通過驗證 |
| 合法重複路徑 | Snapshot 兩項 Path 相同 | 保留兩個 ItemIndex 與兩個要求 |
| 導覽逾時 | A 一直不是目標 | 不開始該 Group 下一項 |
| 視窗候選多個 | 多個新視窗路徑皆符合 | 不取第一個 |
| Group 隔離 | Group 2 歧義，Group 3 正常 | Group 3 可完成 |
| 結果完整性 | 第 3 項失敗 | 1/2 已完成、3 不明、4+ 未嘗試 |
| stale retry target | HWND 重用／PID 時間不符 | 拒絕操作 |
| retry 選擇 | 重複索引、Verified、不明未授權 | 明確拒絕，不新增 Tabs |
| checkpoint 失敗 | 寫檔權限／磁碟錯誤 | 停止後續副作用並輸出摘要 |
| crash 邊界 | 最後紀錄為 InvokeAttempted | 下次不自動重送 |
| deadline | 多輪 transient errors | 不重設 7 秒偵測總預算；遇無法返回的外部 COM/UIA 呼叫須獨立標為限制 |
| retry 診斷與歸因 | 部分異常後停止 Group 2 | 報告含 `MaxRetriesConfigured`、`RetryAttemptsUsed`、`PollCount`、`DetectionElapsedMs` 與實際 `ReasonCode`；Group 3 繼續 |

使用 Pester mock 或注入 adapter 對副作用次數做斷言。不要只驗證字串 warning；主要驗證是否操作了不該操作的物件及是否遺漏結果。

### 10.2 實機驗收

- 基本回歸：README 的 2 視窗／3 Tabs。
- 接近 Backlog 的 6 組多分頁配置，包含重複資料夾路徑。
- 在原 Windows 11 / Horizon VDI 環境測試冷啟動、一般負載與較慢回應。
- 自動化 fixture 模擬特定延遲；不要以「實機剛好沒發生」取代錯誤路徑測試。
- 還原期間在另一個 Explorer 視窗操作：不應混入目標候選。
- 在目標視窗同時新增／關閉分頁：必須拒絕歧義，不能改寫既有分頁路徑。
- 發生部分失敗後，用報告明確補做指定 Group 的指定項目，確認沒有重新建立整組。
- 關閉目標視窗後使用舊報告：拒絕猜配。

建議在原支援環境進行 20 次正常多 Group 還原，逐次記錄驗證結果及耗時；這是初始發布門檻，不代表統計上證明零失敗。測試產生的視窗由測試人員整理，產品不得增加自動關閉／殺程序的清理邏輯。

## 11. 驗收條件與失敗處置

- [ ] 偵測 retry 的任何路徑都不會再次 Invoke 或重新 Navigate；每個新增交易 Invoke 最多 1 次。
- [ ] `MaxRetries=3` 精確代表「首次異常觀測後最多 3 次額外觀測」，預設 backoff 為 200／400／800 ms，設定值可調且無效輸入不觸發 Explorer 副作用。
- [ ] 偵測階段含 retries 共用 7 秒 deadline；無候選時 200 ms 正常輪詢不消耗 retry 次數，接近期限可提前結束。
- [ ] 在恢復、耗盡、提早中止時均記錄實際 retry 次數及失敗原因；不將曾有兩個不同候選的交易誤判為已恢復。
- [ ] 可恢復的延遲／相同 Identity 重複列案例能完成。
- [ ] 兩個不同候選、曾經多候選、身分替換等案例均不會猜選。
- [ ] 同一路徑的既有分頁不能讓新的錯誤分頁被誤判成功。
- [ ] Group 失敗時，當前項目與後續項目均記錄，已完成項目不遺失。
- [ ] 手動補做可指定目標視窗與原始項目索引；過期目標會被拒絕。
- [ ] 原 Snapshot 保持不變；Capture / Preview 基本行為回歸通過。
- [ ] 沒有新增 SendKeys、Clipboard、關閉視窗或重啟 Explorer 行為。
- [ ] 已記錄實測環境、實際根因證據及尚未解決限制。

若 COM Identity 在支援環境無法穩定對應可操作分頁，或 Shell COM 經常無聲漏列，應停止宣稱此策略可安全自動恢復，保留報告與保守中止，另行設計可靠的身分映射。不要以增加 sleep 或挑第一個候選作為發布前的臨時補丁。

若 UIA／COM 呼叫本身會長時間阻塞，另開 worker 隔離方案評估；不能把輪詢 timeout 寫成已提供嚴格 wall-clock 上限。終止觀測 worker 亦不能被誤認為取消了已送給 Explorer 的動作。

## 12. 方案取捨

| 方案 | 判定 | 原因 |
| --- | --- | --- |
| 整段 Add + Detect + Navigate retry | 不採用 | 有重複建立與誤導覽風險 |
| 一律增加 Sleep | 不作主要修復 | 無法處理多候選歸因與不完整 baseline |
| 多候選選第一個／作用中分頁 | 不採用 | 缺乏與本次 Invoke 的可靠關係 |
| 只刪掉多候選 throw，等待變成一個 | 不採用 | 多轉單可能只是列舉遺漏或分頁被關閉 |
| 穩定 baseline + 單次 Invoke + 有界觀測 + 候選歷史 | 建議 | 可處理部分暫時性問題，保留安全停止 |
| UIA 與 COM 深度映射 | 證據需要時另評估 | 複雜度與 Windows 版本依賴較高 |

這個修復的成功標準是：**能確認的暫時性問題自動恢復；無法確認的情況不誤操作，且使用者有完整、精確的補做依據。**

## 13. 參考資料

專案來源：2026-11-01 核對的 `resume-explorer.ps1`、`Backlog.md`（新增第 36–44 行）、`README.md`，HEAD `f4cc418`。前次對話用於定位 Issue，實際需求與程式判斷以本次檔案為準。

1. Microsoft Learn — [Rules for Implementing QueryInterface](https://learn.microsoft.com/en-us/windows/win32/com/rules-for-implementing-queryinterface)：COM 物件 identity 契約。
2. Microsoft Learn — [Marshal.GetIUnknownForObject](https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.marshal.getiunknownforobject)：取得 IUnknown 與參考計數配對。
3. Microsoft Learn — [InvokePattern.Invoke](https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.invokepattern.invoke)：UI Automation 動作請求、非同步返回與可能阻塞的限制。

上述官方資料支持 API 語意，不直接證明 Windows 11 Explorer 特定 build 的分頁曝光、HWND 分組或 COM 物件生命週期；這些部分必須透過階段 A 的實測建立依據。
