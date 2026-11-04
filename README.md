# Resume Explorer

輕量的 Windows 11 File Explorer 視窗與分頁（Tabs）備份／還原工具，使用 **PowerShell、Shell COM 與 Windows UI Automation**，不需安裝第三方套件。

> **Beta 版本：`0.1.0-beta.1`（實驗性）**  
> 在一台 Windows 11 Enterprise 23H2（Build 22631）的 VMware Horizon VDI 上，已實測 `Capture` 和 `Restore` 可將 **2 個視窗、3 個 Tabs** 還原為原本的視窗／分頁分組。此結果不保證適用於其他 Windows 或 Horizon 版本。

目前程式包含 **Issue-2 修復候選版 `0.1.0-beta.1+issue2`**。上述實機結果屬於原 beta.1，不能當作此修復的實機驗收。原 VDI 重現、根因歸因與 20 次正常多 Group 還原尚待完成，因此尚未標記 beta.2；Issue-2 已按核心修復實作完成而結案，但實機驗收仍待完成。自動測試及限制見 [Issue-2 實作驗證](ISSUE2-VALIDATION.md)。

## 功能

- **Capture**：讀取目前的 File Explorer 視窗及可辨識的資料夾 Tabs，按視窗 HWND 分組，寫入 JSON Snapshot。
- **Preview**：顯示 Snapshot 內容，並檢查其中的本機資料夾路徑是否仍存在。
- **Restore**：依 Snapshot **新增** Explorer 視窗，在對應視窗中新增 Tabs，再導向記錄的資料夾。
- 不使用全域 `SendKeys`、不修改 Clipboard、不修改 Registry、不更改 PowerShell Execution Policy。
- 不需要手動輸入 `OPEN` 或其他確認文字。

**尚未提供** `Restart` / 一鍵重啟 Explorer 功能。`Restore` **不會**關閉既有視窗，也**不會**終止 `explorer.exe`。

## 系統需求

- Windows 11（主要在 **23H2 / Build 22631** 環境驗證）
- **Windows 上的 PowerShell 7（`pwsh.exe`）為唯一正式支援的 PowerShell 主版本**；Windows PowerShell 5.1（`powershell.exe`）不再列入開發、回歸測試或問題修復的相容性要求。現有離線測試已在 PowerShell 7.6.1 驗證；其他 7.x 小版本及實際 Explorer／VDI 互動仍須分別驗收。
- 僅支援 Windows 上的 PowerShell 7；Shell COM、Windows UI Automation 以及 Explorer Tabs 依賴 Windows，不支援以 macOS／Linux 上的 PowerShell 7 執行。
- 允許執行本機 PowerShell 腳本的公司／系統政策

在公司管理的 VDI 上，請遵守 IT 對 PowerShell 與自訂工具的規範；不要為了執行本工具繞過公司 Execution Policy。

## 安裝

將 `resume-explorer.ps1` **及同目錄的 `resume-explorer.core.ps1`** 一起放到你選擇的資料夾，例如：

```text
D:\_tools\_wins\resume-explorer.ps1
```

以下指令使用此路徑作為範例；請依實際位置修改。

## 使用方式

### 1. 擷取目前視窗與 Tabs

```powershell
& "D:\_tools\_wins\resume-explorer.ps1" -Action Capture
```

範例輸出：

```text
Saved 2 window(s), 3 tab(s): C:\Users\<username>\AppData\Local\Temp\ExplorerTabs-snapshot.json
  Window: D:\some\path | D:\another\path
  Window: E:\more\other\path
```

預設 Snapshot 路徑：

```text
%TEMP%\ExplorerTabs-snapshot.json
```

每次 `Capture` **會覆寫**該 Snapshot。若要保留不同時間的版本，請指定不同檔名。

### 2. 預覽 Snapshot

```powershell
& "D:\_tools\_wins\resume-explorer.ps1" -Action Preview
```

預覽中的 `[True]`／`[False]` 表示資料夾路徑在檢查當下是否存在。

### 3. 還原視窗與 Tabs

```powershell
& "D:\_tools\_wins\resume-explorer.ps1" -Action Restore
```

`Restore` 會依 Snapshot **另外開啟**視窗與 Tabs；不會關閉或合併目前已開啟的視窗。重複執行可能產生重複視窗／Tabs，請先檢查實際結果。

### 4. 自訂 Snapshot 路徑（選用）

```powershell
& "D:\_tools\_wins\resume-explorer.ps1" -Action Capture -Snapshot "D:\_tools\_wins\my-tabs.json"
& "D:\_tools\_wins\resume-explorer.ps1" -Action Preview -Snapshot "D:\_tools\_wins\my-tabs.json"
& "D:\_tools\_wins\resume-explorer.ps1" -Action Restore -Snapshot "D:\_tools\_wins\my-tabs.json"
```

## 技術原理

### Issue-2 安全辨識與報告

每個額外分頁的交易，先取得至少三次相同身分集合、跨越 600 ms 的可信 baseline（最長 3 秒），才呼叫一次 AddButton / Invoke。後續重試只讀取觀測，絕不再次建立分頁或重送 Navigate2。

- 每個 Tab 的偵測預設 **15 秒總期限**，一般 polling 為 **200 ms**；暫時性讀取錯誤依 **200 / 400 / 800 ms** 退避，持續錯誤時上限維持 800 ms。可信觀測使連續錯誤次數歸零，沒有固定三次重試上限。
- 唯一候選須持續可信穩定 600 ms，且安定期也包含在同一偵測期限內。真實多候選、曾經多候選、baseline 身分消失或候選更換時，停止該 Group，不猜選分頁；其他正常 Group 繼續。
- Navigate2 只對確認的候選呼叫一次，並以同一 Identity 連續觀測到目標路徑來驗證（最長 10 秒）。舊的同路徑分頁不能代替候選通過驗證。Invoke 拋出例外時，即使看見候選也不會自動導覽。
- 新視窗用 RootHwnd 去重，遇到多個候選即保守停止。Capture 與分頁交易保留原本 RawHwnd 分組；RootHwnd 僅用於視窗候選去重、指紋及 UIA 查找。這個分組模型仍需原 VDI 驗證。

15 秒是 **Invoke 返回後的單次觀測期限**；baseline、新視窗辨識和 navigation 各有獨立預算。同步 COM / UIA 呼叫如果卡住，輪詢計時器不能中斷它，故沒有嚴格的整次操作 wall-clock 上限。背景還原／不搶焦點仍是未實作需求。

Restore 明確以 `-WindowStyle Normal` 請求可見的 Explorer 新視窗。已修正候選版曾誤用 `Hidden`，造成路徑全部 Verified、視窗卻不可見的 regression。`Verified` 仍表示身分／路徑驗證，不表示已驗證桌面可見性或焦點狀態。此修正作用於之後的新視窗建立，既有隱藏視窗不會自動顯示；請先檢查先前還原結果，避免重複執行整組 Restore。

```powershell
.\resume-explorer.ps1 -Action Restore -Snapshot .\my-tabs.json `
    -ReportPath .\run.json -DetectionTimeoutSeconds 20 `
    -PollIntervalMs 200 -TransientErrorBackoffMs 200,400,800 `
    -StableDurationMs 600 -BaselineTimeoutSeconds 3 -NavigationTimeoutSeconds 10
```

所有時間及 backoff 必須為正數，backoff 不可為空。預設報告位置是 `%LOCALAPPDATA%\ResumeExplorer\Runs\<RunId>.json`；指定的 ReportPath 必須是新檔案。原 Snapshot 不修改。報告含原始一基索引（略過無效路徑也不重新編號）、來源 SHA-256、視窗指紋、每次觀測及錯誤診斷，包含 Path，因此請妥善保存。

| Status | 意義 |
| --- | --- |
| Verified | 該身分已觀測為目標路徑 |
| NotAttempted | 尚未送出建立請求 |
| PreconditionFailed | 建立前條件不成立，沒有 Invoke |
| OutcomeUnknown | 可能已建立／導覽，無法確認 |
| SkippedInvalidPath | 無效或目前不可存取的路徑 |

`ReasonCode` 另記歧義、身分變化、逾時或觀測不完整等原因。`Completed` 表示此次流程已結束，**仍須查看項目 Status**；全域 Shell 不可用或 checkpoint 寫入失敗會停止整次 Restore。每次副作用前寫入 Attempted checkpoint，結果以同目錄暫存檔原子置換保存；突然中斷留下的 Attempted 必須視為結果不明。明細保存在同一 JSON 的 `Diagnostics.Samples`，含 Phase、時間、Raw/Root HWND 及該 run 內有效的 COM Identity；不是可跨程序重用的分頁 ID。

### 還原結果摘要

Restore 與 Retry 共用結果摘要。第一行仍是當次 JSON 報告路徑；`Completed` 表示流程結束，`Verification` 才區分全部驗證、部分未驗證、中止或空結果。`Verified` 仍僅代表既有身分／路徑驗證，不表示視窗可見性或完整工作階段恢復。

全部驗證完成的範例：

```text
Report: C:\Runs\complete.json (Completed)
Restore summary:
  Verification: Complete
  Total: 3
  Verified: 3
  Not verified: 0
All 3 items verified.
```

部分未驗證會逐項列出原始索引、完整路徑、Status 及有值的 ReasonCode；重複路徑仍分別列出，換行／控制字元會跳脫顯示，原始 JSON 值不變。例如：

```text
Report: C:\Runs\partial.json (Completed)
Restore summary:
  Verification: Partial
  Total: 3
  Verified: 1
  Not verified: 2
  OutcomeUnknown: 1
  NotAttempted: 1

Unverified items:
  Group 2:
    Tab 3 | OutcomeUnknown | AmbiguousCandidates
      Path: D:\Work\Project\Notes
    Tab 4 | NotAttempted
      Path: D:\Work\Project\Reports
WARNING: 2 of 3 items were not verified.
Review retry options:
  & 'E:\_projects\tools\scripts\resume-explorer\resume-explorer.ps1' -Action PreviewRetry -ReportPath 'C:\Runs\partial.json'
```

提示會依目前安裝位置與當次報告產生可從任意目錄執行的完整指令，並正確引用空白與單引號；**不會自動執行補做**。PreviewRetry 會列舉目前 Explorer 目標並在報告旁寫入 `.retry-preview.json`，Shell 不可用時可能失敗；仍可直接閱讀原 JSON 的詳細診斷。OutcomeUnknown 是結果不明，補做時仍須明確選取並使用 `-IncludeUncertain`。

流程中止時，首行狀態改為 `(Aborted)`，摘要顯示 `Verification: Interrupted`、實際計數及未驗證明細，並另外警告：

```text
WARNING: Restore run aborted; inspect the report and error before retrying.
```

原始例外仍會往外傳遞，即使當前項目全是 Verified 也不會宣稱整次 run 成功。空 run 顯示 `Verification: Empty`、零項目與 `No restore items were found.`，不提供補做指令。若最終 checkpoint 寫入失敗，仍保留原 warning、記憶體 JSON fallback 和例外；顯示的報告路徑不代表磁碟檔案已同步。

Retry 子 run 的 Total 只計算本次選取項目，Report 指向該次 child JSON；判斷整個原 Snapshot 的狀態仍須檢視原報告與子報告。

### 指定 Group 與項目補做

先檢查 Explorer 畫面，執行預覽取得目前 HWND 及指紋，再明確選擇項目。PreviewRetry 會在報告旁建立 `.retry-preview.json`；預覽指紋或來源報告變更時必須重新預覽。

```powershell
.\resume-explorer.ps1 -Action PreviewRetry -ReportPath .\run.json
.\resume-explorer.ps1 -Action Retry -ReportPath .\run.json `
    -GroupIndex 2 -TargetHwnd 123456 -ItemIndexes 4,5
# 檢查畫面後，明確包含結果不明的項目：
.\resume-explorer.ps1 -Action Retry -ReportPath .\run.json `
    -GroupIndex 2 -TargetHwnd 123456 -ItemIndexes 3 -IncludeUncertain
```

補做一律在指定現存視窗**新增**所選項目，不重用或整理遺留空白分頁，不以相同 Path 自動略過。拒絕重複索引、Verified 及未明確授權的不明項目。新報告存於來源報告旁的 `RetryRuns`，保留 ParentRunId / RootRunId；同一來源家族的子報告會檢查已完成／曾嘗試項目，並以排他鎖防止同時補做。請保留整個報告家族及原報告位置，刪除／移動檔案會破壞此查核；此機制不提供跨 crash 的 exactly-once 保證。

### 執行離線測試

```powershell
& .\tests\Issue2.Tests.ps1
& .\tests\RestoreSummary.Tests.ps1
& .\tests\ExplorerSmoke.Tests.ps1
& .\tests\ExplorerSmoke.OneClick.Tests.ps1
```

測試以注入的時鐘和觀測 adapter 驗證副作用次數，不操作實際 Explorer，也不需安裝 Pester。

### PowerShell 7 真實 Explorer smoke runner（Task-5）

Runner 已提供，**Task-5 已依使用者 Win11 VM 的 E01／E02 完成畫面結案**（2026-11-02，整體 Exit 0）。這是本次 VM 的使用者實機驗收，不是所有 Windows／PS7／VDI 的相容性保證；精確 VM build／PS minor 與原始 Report 尚未由 agent 重新讀取，見[證據與限制](tests/Integration/TASK5-VM-ACCEPTANCE.md)。一般開發沙箱不等於 Explorer 隔離環境，後續重跑仍不得在工作中的 Explorer／Horizon session 執行。操作見 [Integration SOP](tests/Integration/README.md)。

```powershell
# 安全預設：不讀 COM／UIA、不啟動 CLI 或建立 fixture；回報 NotRun、Exit 2。
pwsh -NoProfile -Sta -File .\tests\Integration\Invoke-ExplorerSmoke.ps1
```

只有在獨立可重設的 Windows 11 互動桌面，提供綁定實際 SID／Session／Desktop 的隔離聲明、確認全域 Explorer scope 並明確指定 `-AllowExplorerUiChanges`，才允許 Run 透過真實 CLI 執行 E01 Capture／Preview／Restore 或 E02 PreviewRetry／Retry。Prepare 不開 Explorer；Run 的獨立 observer 通過後為 AwaitingVisualReview／Exit 2。可選人工目視 Confirm，或用新增的唯讀 Verify 再核對 hash／即時 scope 後 Passed，後者明確記錄 VisualReview NotRun。所有證據使用唯一 TEMP root，不重用預設 Snapshot／正式 Runs；不自動重跑，不宣稱同步 COM／UIA 有 hard timeout。

開發初版 PS7.6.1 離線測試 **39＋17＋21 = 77** 項通過，僅驗證 harness 安全與合成流程；後續 GUI 通過依據為使用者的 VM 截圖與目視確認，不能以離線結果代替。Task-5 已結案，產品 CLI／Schema／既有測試未因結案改動。

**一鍵入口**：在獨立 Win11 VM 雙擊 `tests\Integration\Run-ExplorerSmoke.cmd`，或執行 `pwsh -NoProfile -Sta -File .\tests\Integration\Start-ExplorerSmoke.ps1 -Run`。啟動時一次授權關窗與測試；既有 Explorer 可選先 Capture 保存配置，再透過系統整窗關閉命令 `WM_SYSCOMMAND / SC_CLOSE` 關窗，不終止程序。預設自動驗證 E01／E02 並清理已驗證測試視窗，無須 PASS／CONTINUE；加 `-RequireVisualReview` 可選人工目視。備註／截圖標為 Optional。多組關窗採逐窗投遞一次、等待可靠觀測收斂，每次關窗作業全部目標共用 10 秒；未知視窗、身分變更、保存不完整或逾時仍停止並保留 ledger／觀測時序。無 `-Run` 時零 dispatch。新版 **126 項離線測試通過，使用者 VM 的自動流程亦已 Exit 0／Error null**；VisualReview NotRun 為自動模式正常結果。這是單次主要流程驗收，延伸矩陣未全部實測。詳見 [一鍵 SOP](tests/Integration/ONE-CLICK.md)、[驗收證據](tests/Integration/TASK5-VM-ACCEPTANCE.md)、[修復進度](plans/resume-explorer-Task-5-multi-group-close-regression-plan.md)。

### 原有流程

1. `Shell.Application.Windows()` 取得 Explorer 的 Tab 導覽物件。
2. 以相同的 `HWND` 將 Tabs 分組為同一個 Explorer 視窗。
3. 將各組資料夾路徑存成 JSON。
4. Restore 時透過 `explorer.exe` 開啟每組的第一個資料夾，並等待辨識新視窗。
5. 透過 **UI Automation** 呼叫 Explorer 的 `AddButton`（New Tab）的 `InvokePattern`，建立額外分頁。
6. 透過 Shell COM `Navigate2()` 將新分頁導向指定資料夾。

不透過全域鍵盤模擬操作其他應用程式，也不使用 Clipboard 傳遞路徑。

## 已知限制與注意事項

- **尚無 Restart 功能**：目前用途是 Capture / Preview / Restore。不可將本版當成已可一鍵重啟並還原的工具。
- **Restore 只新增，不取代**：原本的 Explorer 視窗仍會保留。
- **分頁順序／作用中分頁**：目前不保證完整恢復原本的 Tab 順序、焦點、歷史紀錄、視窗大小與位置。
- **僅擷取實際存在的檔案系統資料夾**：`Capture` 使用 `[IO.Directory]::Exists()` 過濾；例如「本機」、「首頁」、特殊 Shell Namespace、失效或當下無法存取的路徑，可能不被擷取。
- **UI Automation 依賴 Explorer 控制項**：若不同 Windows 版本更改 `AddButton` 或 UI 結構，新增 Tab 可能失敗。
- **逾時／競態條件**：虛擬桌面負載、Explorer 啟動速度或系統焦點變化，可能讓部分分頁還原失敗；請檢查實際結果，不能只根據 `Requested new tab` 訊息判定完全成功。
- **Snapshot 含資料夾路徑**：可能包含個人資料夾路徑或使用者名稱。請保留在適當權限的位置，不要公開上傳。
- **工作中檔案操作**：本版不會重啟 Explorer，但正式使用前仍應避免在大量檔案搬移等操作進行時做測試。

## 已驗證的測試

| 測試 | 結果 |
| --- | --- |
| 在 VMware Horizon VDI 上擷取 2 個 Explorer 視窗、3 個 Tabs | 通過 |
| 以相同 HWND 將多個 Tabs 分組 | 通過 |
| `Restore` 建立 2 個視窗並將 3 個 Tabs 分組 | 通過（使用者目視確認） |
| 不使用 SendKeys／Clipboard 的 Tab 還原 | 通過（上述測試） |
| 自動重啟 `explorer.exe` 並還原 | **未實作／未測試** |

## 疑難排解

**`Snapshot not found`**：先執行 `-Action Capture`，或確認 `-Snapshot` 指向正確 JSON 檔案。

**`no NEW Explorer window detected`**：工具未在等待時間內辨識到新視窗，該組剩餘 Tabs 會跳過；檢查是否已有同路徑視窗、Explorer 是否異常或啟動是否太慢。

**`Explorer AddButton not found`**：UI Automation 沒找到該版本 Explorer 的新增 Tab 控制項；請停止進一步 Restore 測試，檢查 Windows 版本與 UI 狀態。

**顯示 `Requested new tab`，但結果不符**：此訊息表示嘗試新增／導向；仍需目視核對 Tabs 是否位於正確視窗。

## 後續規劃

- [ ] 在 Capture 成功、Snapshot 驗證通過後，新增可控的 `Restart & Restore` 流程。
- [x] Issue-2 候選版提供身分／路徑驗證與逐項結果報告；實機發布驗收待完成。
- [ ] 加強 Tab 順序、目前作用中的 Tab 與視窗位置還原。

## 安全與合規

本版本沒有網路傳輸、Registry 修改、執行政策繞過或 `explorer.exe` 強制終止邏輯；**技術上沒有明顯危險**。

## 持久 Snapshot 與還原提示
持久還原提示（本次實作，待 VM 互動驗收）：選 S 後，配置保存在 `%LOCALAPPDATA%\ResumeExplorer\Snapshots\BeforeSmoke\<RunId>.json`，同目錄有 `.recovery.json` 驗證紀錄及 `.restore.txt` 完整 PowerShell 7 還原命令。這些檔案在關窗前提交，不覆寫日常預設 Snapshot、不自動刪除或 Restore。前景 supervisor 等待 worker 結束後，在 JSON 後顯示還原提示；worker crash 時可依 RunId 找回，整個終端也被關閉時請查看持久命令檔。原有 suite/case 測試證據仍保存在 TEMP。新增 10 項離線 recovery 測試，總基準為 39＋17＋23＋47＋10＝136。先前 VM 截圖不代表本次 supervisor／互動流程已驗收。
