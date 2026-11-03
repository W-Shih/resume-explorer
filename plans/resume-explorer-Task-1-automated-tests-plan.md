# Resume Explorer — Task-1 Automated Tests 實作計畫

日期：2026-11-01  
狀態：設計提案；**尚未實作測試、未執行 Explorer Restore**  
對應：`Backlog.md` 第 64–67 行 Task-1，以及「[resume-explorer] 迭代 - 1」的 Automated tests 建議  
目標：可重複的 Unit test gate + 安全、明確啟用的 Windows Explorer E2E smoke test

## 1. 核心結論

採用 **Pester 單元／元件測試 + 專用互動式 Windows 桌面上的 E2E smoke test**。這不是單純累積 JSON unit tests 的工作；現有程式最大風險是 Shell COM、UI Automation、非同步時間差與對錯誤分頁進行導覽。

1. 最小化抽出可安全 import 的測試邊界。Import module 時不得觸發 `Preview`、`Capture`、`Restore`。
2. 先完成 Snapshot 基本測試，再為 Restore 的 side effects 加上可觀測、可 mock 的呼叫介面。
3. **優先建立真正的 2 視窗／3 Tabs E2E smoke test**；不要等到大量罕見 JSON cases 全寫完才做真實分組測試。
4. 隨 Issue-2 修復的實作，加入「一次建立請求、有限觀測重試、歧義不導覽、結果可追蹤」的測試矩陣。
5. Unit 預設可自動／CI 執行；Integration 必須顯式 opt-in 且限制在隔離測試桌面。

## 2. 已核對的 Repository 現況

- Repo：`E:\_projects\tools\scripts\resume-explorer`。
- 查閱時 HEAD：`dd179de`；查閱時 Git 工作樹乾淨。
- 既有腳本：`resume-explorer.ps1`，`0.1.0-beta.1`，151 行；單檔同時包含 Snapshot 邏輯、Shell COM、UI Automation 和 Action dispatch。
- 受版本控制的檔案尚無 `tests/`、測試 runner 或測試 fixture。Commit `cf67238` 雖以「新增自動化測試」命名，實際 diff 只新增 Backlog 的 Task-1 和 Task-2，沒有測試程式。
- README 記錄曾在 Windows 11 Enterprise 23H2 / Build 22631、VMware Horizon VDI 人工驗證 2 視窗／3 Tabs；**不代表其他 Windows 環境已通過 E2E**。
- 目前連線裝置 Windows PowerShell 為 **5.1.22621.6931**、`pwsh` 為 **7.6.1**；兩者能列到的 Pester 都只有 **3.4.0**。建議 Pester 5.x，但目前**尚未安裝／驗證**，不可假稱測試已能執行。

### 2.1 程式上可確認的測試缺口

| 現有部分 | 行為與風險 | 需要的測試邊界 |
| --- | --- | --- |
| `switch ($Action)` | Dot-source / 直接載入會執行 Action；預設 `Preview` | 薄 CLI entrypoint 與純載入 module |
| `Save-Snapshot` | 真實 Shell views + `Directory.Exists` + `WriteAllText` | 注入 views、用獨立測試檔驗證 JSON |
| `Read-Snapshot` | 只明確檢查檔案存在與 Version 1 | schema validation、各種 JSON 錯誤 |
| `Get-ExplorerTabViews` | Shell COM + 部分空 `catch {}` | 假 observation／獨立 adapter |
| `Wait-NewExplorerWindow` | 多匹配時直接取第一個 HWND | 歧義測試、不得猜目標 |
| `Add-ExplorerTab` | 呼叫 UIA `InvokePattern.Invoke()` | 假 Invoke、計數及例外注入 |
| `Wait-NewTab` | 7 秒輪詢，遇兩個候選就 throw | 假時鐘、候選歷史、有限 retry |
| `Navigate2` | 直接作用在 COM object | 注入 wrapper、驗證正確 identity |
| 導覽後檢查 | 同 HWND 任意 Tab 路徑符合就算找到 | 排除既有同路徑分頁假陽性 |
| `Restore-Snapshot` | 主要寫 Host/Warn，Group 失敗後 break | 結構化 status、未執行 item 記錄 |

### 2.2 工作範圍與相依性

- **Task-1** 是測試基建；不是直接修好 Issue-2。
- **Issue-2** 的完整修復依 `resume-explorer-Issue-2-fix-plan.md`：stable baseline、Invoke-once、觀測 retry、候選歸因、navigation verification、checkpoint、手動指定 Group/Items retry。本文件設計對應的驗收測試，不重新發明演算法。
- **Task-2** 要求不存在的路徑 warning + skip、不中斷其他項目。目前 Restore 只會靜默過濾。它是**未實作的預期測試**，不可標記為現況已通過。
- **Issue-1** 的 ZIP／Shell namespace 不是目前支援的資料夾範圍，不應藉 Task-1 偷偷改變功能。
- **Feature Request-1** 的背景還原／不彈窗／不搶焦點仍為獨立需求；E2E 可觀測焦點，但**不宣稱本 Task 解決**。

## 3. 絕對安全條件

1. **Unit 必須零真實 Explorer 副作用**：不得真的執行 `Shell.Application`、`Start-Process explorer.exe`、`AddButton.Invoke`、`Navigate2`，也不能關閉 Explorer。
2. 任何單元測試使用 `$TestDrive` 或唯一暫存目錄與顯式 `-Snapshot`；絕不覆寫 `%TEMP%\ExplorerTabs-snapshot.json`。
3. Import 測試模組／探索 tests 時，不執行 Action dispatch、Explorer COM 建立或 UI Automation。
4. 禁止 `SendKeys`、Clipboard 操作、Registry 修改、Execution Policy 變更、重啟／kill Explorer。
5. E2E 永遠不由預設 Unit、一般 CI、test discovery、Git hook 意外觸發；必須指定 `Integration` suite 和副作用授權 switch。
6. E2E 只在**專用的互動式 Windows 11 測試使用者 session** 進行；背景 remote shell 或 Session 0 不視為合格。
7. 測試資料夾用唯一 RunId；僅在明確確認全是測試視窗時操作。Cleanup 以人工確認／手動關閉自己的測試視窗為主，絕不關閉未知視窗。
8. Mock 使用 synthetic HWND／Identity／路徑。診斷資料及 CI artifact 不應外洩私人資料夾路徑。

## 4. 最小架構修改建議

不把 151 行的小工具改寫成大型架構。建議**薄 CLI + 單一無載入副作用的 module**，再用 adapters 將純邏輯和平台副作用分離：

~~~text
resume-explorer/
├── resume-explorer.ps1                 # 保留既有 CLI 與預設 Action
├── src/
│   └── ResumeExplorer.psm1             # Import 不執行任何 Action
├── tests/
│   ├── Invoke-Tests.ps1                # 預設 Suite=Unit
│   ├── Unit/
│   │   ├── Snapshot.Tests.ps1
│   │   ├── GroupingAndPaths.Tests.ps1
│   │   ├── RestoreDecisions.Tests.ps1
│   │   └── RestoreFlow.Tests.ps1
│   ├── Integration/
│   │   └── Explorer.Smoke.Tests.ps1
│   └── Fixtures/
│       └── README.md
├── Backlog.md
├── README.md
└── resume-explorer-Issue-2-fix-plan.md
~~~

**相容性**：`resume-explorer.ps1 -Action Capture|Preview|Restore -Snapshot <path>`、預設 `Preview`、Snapshot v1 和主要 CLI 使用方式維持。不要為了測試而在產品腳本加入測試專用的神祕環境變數；只把末端 `switch` 留在 entrypoint。

| 待抽取責任（名稱為提案） | 類別 | 單元測試方式 |
| --- | --- | --- |
| `ConvertTo-SnapshotData`、`Test-SnapshotSchema` | 純邏輯 | 合成資料／JSON fixture |
| `Read-SnapshotFile`、`Write-SnapshotFile` | 檔案 adapter | `$TestDrive` 真實暫存檔 |
| `Group-ExplorerViews`、`Get-RestorableItems` | 純邏輯／Exists adapter | 假 HWND、Path、Identity |
| `Get-ExplorerObservation`、`Start-ExplorerWindow` | 平台 adapter | Mock；E2E 才真的呼叫 |
| `Invoke-NewTabOnce`、`Navigate-ExplorerTab` | 平台 adapter | Mock 次數、目標與例外 |
| `Resolve-NewTabCandidate` | Issue-2 純邏輯 | baseline + 完整觀測歷史 |
| `Wait-NewTabCandidate`、`Wait-TabNavigation` | orchestration | fake observation／clock／sleep |
| `Restore-Group`、`Restore-Snapshot` | orchestration | 假 adapter + status assertions |

第一個 PR 只需抽出**import 邊界、Snapshot 與必要 UI wrappers**；Issue-2 專屬函式隨該修復 PR 實作。Pester 對 module 內函式的 mock 須使用官方的 module scope mock 或 `InModuleScope`，並有測試確認真正攔截到 side effects。

## 5. Snapshot v1 契約與處理政策

目前 Capture 的資料型態如下（示意）：

~~~json
{
  "Version": 1,
  "CapturedAt": "2026-11-01T07:00:00.0000000-08:00",
  "Windows": [
    {"Paths": ["C:\\Test\\A", "C:\\Test\\B"]},
    {"Paths": ["C:\\Test\\C"]}
  ]
}
~~~

建議明確規定：

- `Version` 必須是支援的整數 `1`；缺少／不支援／錯型別要拒絕，不依賴 PowerShell `-eq` 的隱式強制轉型。
- `Windows` 必須存在且為 JSON array；`Windows: []` 是合法空 Snapshot，不必 Restore。
- 每個 Window 需要 `Paths` array；`Paths: []` 不開視窗，記錄 `SkippedEmptyGroup`。
- `CapturedAt` 應可解析 ISO 8601 timestamp；如果要容忍舊 Snapshot 缺值，需明訂 compatibility policy，再寫對應測試。
- 有效路徑仍以**現存 filesystem directory** 為界；不可把 ZIP 檔當作已支援功能。不存在／空／無效 Path 按原 `ItemIndex` 警告並 skip（Task-2）；結構性缺少整個 `Paths` array 則是 schema error。
- 相同 Path 的兩個 Tabs 是合法的兩個 item；**不得去重**。兩個 Groups 中出現相同 Path 亦合法。
- 一個 Group / 一個 Path 仍須輸出 arrays，不可在 PowerShell pipeline 中不慎攤平成 scalar。
- 路徑中的 Unicode、空白、合法特殊字元原樣 roundtrip。比較路徑時不因錯誤正規化混淆磁碟根目錄、UNC 或不同檔案系統資源。
- 無法讀取、非法 JSON、schema 無效，`Restore` 在**任何** UI 動作前 fail closed。
- JSON 維持 UTF-8（無 BOM）的現有 WriteAllText 行為。原子保存屬選用加固；有實作才要求「寫入失敗保留舊 Snapshot」測試。

## 6. 測試矩陣

### 6.1 P0 — Snapshot、CLI 邊界的首批測試

| ID | 測試情境 | 斷言 |
| --- | --- | --- |
| S01 | Import module | 0 次 Action、Explorer COM/UIA、檔案寫入 |
| S02 | Capture：2 HWND、共 3 Tabs | 2 Groups/3 Paths；分組正確，不儲存 HWND |
| S03 | Capture：0 個可辨識資料夾 | `Windows: []`，正常完成 |
| S04 | 1 Window / 1 Path roundtrip | arrays 不退化為 scalar |
| S05 | Unicode／空白路徑 | UTF-8 roundtrip 不失真 |
| S06 | 同 Group 重複 Path | 兩項保留、沒有去重 |
| S07 | 指定 Snapshot | 僅動到測試路徑，不碰預設 Snapshot |
| S08 | Snapshot 不存在／不可讀 | 清楚報錯，Restore 0 次副作用 |
| S09 | 壞 JSON | 拒絕，Restore 0 次副作用 |
| S10 | Version 錯／缺失 | 拒絕，Restore 0 次副作用 |

### 6.2 P1 — Schema、Path、Group 與 Task-2

| ID | 場景 | 必須驗證 |
| --- | --- | --- |
| V01 | 缺少 Windows／Windows 不是 array | schema error；不 Restore |
| V02 | Group 缺少 Paths／Paths 不是 array | schema error；不 Restore |
| V03 | 空 Windows、空 Group | 允許空資料；無副作用；有 skip/status |
| V04 | 有效 Path + 不存在 Path + 有效 Path | warning + skip 中間項，其後項仍可處理（Task-2，待實作） |
| V05 | 第一個 Path 不存在 | 保留原 ItemIndex，不把第二項默默改稱 Item 1 |
| V06 | 單一 Path 為 null／空字串／非字串 | 按 item 跳過，其他有效 item 不受影響 |
| V07 | 根目錄、大小寫、尾部分隔符 | 比較行為明確，不破壞 UNC／磁碟根目錄 |
| V08 | 多個 Groups 具有相同 Path | 不合併兩個 Groups |
| V09 | 新窗口候選有多個匹配 | 不直接取第一個、不為錯誤窗口新增 Tabs（Issue-2） |
| V10 | Group 1 全無效，Group 2 有效 | Group 1 skip，Group 2 繼續（Task-2） |

### 6.3 P1 — Restore 安全矩陣（依 Issue-2 逐步實作）

用 synthetic baseline `B`、候選 `A` / `C`、可注入 observation 序列與 fake clock。**不啟動 Explorer、不做真實等待**。

| ID | 注入情況 | 必須驗證的結果 |
| --- | --- | --- |
| R01 | `B → B+A`，候選穩定，導覽達標 | Invoke=1、Navigate=1、相同 identity Verified |
| R02 | 多輪 `B` 後才出現 `A` | 只能重試觀測，Invoke 仍=1 |
| R03 | 永遠只有 `B`，觀測逾時 | Invoke=1、Navigate=0、OutcomeUnknown |
| R04 | `B+A+A`（同一 identity 被重複列出） | 安全去重，仍須保留原始樣本數 |
| R05 | `B+A+C`（兩個不同候選） | Navigate=0，停止 Group，不選第一個 |
| R06 | `B+A+C → B+A` | 曾經歧義不能因候選消失而猜選 A |
| R07 | `B+A → B+C` | 身分不穩，不導覽 |
| R08 | Invoke 前 baseline 不完整或持續變動 | Invoke=0；不能帶著不可信 baseline 操作 |
| R09 | baseline identity 消失／Root HWND 或程序改變 | 停止 Group，不繼續新增 |
| R10 | Invoke 拋例外但 Explorer 可能已收到 | 不重新 Invoke、不自動 Navigate |
| R11 | 舊 Tab 已有目標 Path，新 Tab 未導覽完成 | 舊 Tab 不能導致假 Verified |
| R12 | Navigate2 例外／逾時／候選消失 | 不再 Navigate，也不開始下一 item |
| R13 | Group 2 發生歧義，Group 3 正常 | 局部停止，不影響下一 Group（全域故障除外） |
| R14 | 第 3 item 失敗，後面 item 未嘗試 | 原 index：1/2 Verified、3 Unknown、4+ NotAttempted |
| R15 | 觀測短暫失敗，後續恢復 | 不把錯誤當空集合；deadline 不無限重設 |
| R16 | checkpoint 無法寫入 | 在後續副作用前停止，並揭露記錄失敗 |
| R17 | Retry stale HWND／已 Verified／Unknown 未授權 | 拒絕，Invoke=0 |
| R18 | Retry 要求兩個相同 Path 的 items | 根據 ItemIndex 分辨，而非 Path 去重 |

測試要斷言**副作用數量、執行目標 identity、原始 ItemIndex、status 與 ReasonCode**，不應只比對 `Write-Warning` 的文字。

**重要**：R02–R18 中多個能力目前只在 Issue-2 設計文件中，尚不存在 beta.1 的程式。先把它們列為**expected／待實作的 regression tests**，不要讓 CI 因未完成的另一個 Issue 永遠紅燈，也不能誤報測試已通過。採用「同一 PR 新增實作 + 對應測試轉綠」的節奏。

### 6.4 額外防護案例

- Read only：`-Action Preview` 不開任何視窗、不呼叫 COM、不修改 Snapshot。
- 使用者輸入無效 Snapshot 以及錯誤版本時，恢復前即拒絕，沒有任何 UI side effects。
- Capture 只能使用能辨識的現存資料夾；`H:\fake-path\dummy.zip` 這類原 Issue-1 範例不能在目前版本被誤判已可開啟。
- 路徑不能以字串含 `&`、空白、中文或類似 PowerShell 語法的字元造成額外命令執行；測試應對可安全建立的目錄以 literal path 為準。
- Windows/Tab 的原始多重集合（multiset）對比，不能單純用 `-Unique` 把重複分頁消掉。

## 7. E2E smoke test：驗證真正的 Explorer 視窗／分頁

### 7.1 強制的 preflight gate

E2E 僅能在**專用、互動式** Windows 11 桌面（優先原先測過的 Horizon VDI 類型）由測試人員啟動。Runner 必須確認：

1. 同時提供 `-Suite Integration` 和 `-AllowExplorerUiChanges`；缺少任一參數就拒絕，而不是靜默選擇執行。
2. 當前為 Windows、STA、互動式的**正確使用者桌面 session**；不能把 headless CI、remote background shell、Session 0 視為合格。
3. 測試根目錄為唯一的 `%TEMP%\ResumeExplorer-E2E-<RunId>`，Snapshot 使用其中的唯一檔名。
4. Capture 前必須人工／程式雙重確認當前沒有其他工作中的 Explorer 窗口會被 Capture。因 Capture 目前讀取**全部** Explorer windows，不能在混有使用者窗口時「只驗證自己的項目」並忽略 Restore 會複製其他窗口的風險。
5. Preflight 失敗時**不呼叫** Capture/Restore，也沒有繞過 preflight 的 `-Force` 參數。
6. 不自動終止 `explorer.exe`，不靠殺 Explorer 清理測試環境。測試失敗時保存足夠的診斷資料，停止繼續新增。
7. 若測試工具無法確認 target Window/Tab identity，應標記 `Blocked`／`Failed`，不得亂選候選來使測試變綠。

### 7.2 E01：2 Windows / 3 Tabs，完整 Capture → Restore → Verify

唯一的測試目錄：

~~~text
TestRoot\
├── A\
├── B\
└── C\

Window 1: A | B
Window 2: C
~~~

1. 在乾淨測試 session 由測試人員建立 2 個 Explorer windows；Window 1 有 `A`、`B` 兩個 tabs，Window 2 有 `C` 一個 tab。建立 fixture 的操作**不計入**產品 Restore 成功率。
2. 以顯式 `-Snapshot <TestRoot>\snapshot.json` 執行 Capture。解析 JSON：應恰好有 2 個 Groups / 3 個 Paths；按 group 的 path multiset 應等於 `{A,B}` 和 `{C}`。
3. 記錄 Restore 前的 Explorer HWND / identity / Path baseline。**保留原測試窗口**，直接執行 Restore；由於目前產品只新增視窗，成功應額外出現 2 新視窗及 3 新 tabs，原有 fixture windows 不應被修改。
4. 使用**獨立測試 observer** 對「新視窗集合」驗證分組：一個新窗口有 `A` 與 `B`，另一個有 `C`；既有測試窗口內容保持不變。不能只看總共出現 3 個目標路徑，更不能只看 console 的 `Requested new tab`。
5. 人工目視核對 Explorer UI：Tab 是否真的位於正確 Window；記錄 Windows build、PowerShell/Session、elapsed time、warnings 及觀測到的路徑。
6. 人工確認後**手動關閉自己的測試窗口**，再整理測試根目錄。產品代碼不新增「自動關閉 Explorer」的清理能力。

此案例的主目的為**分組、視窗數、Tabs 數、路徑**；不要求 UI Tab 順序、目前 active tab、focus、窗口大小／位置精確還原（現階段產品未保證）。

### 7.3 後續 E2E 案例

| ID | 情境 | 驗證條件與相依性 |
| --- | --- | --- |
| E02 | 先關閉自己的原 fixture windows，再執行 Restore | 從 Snapshot 建立正確 2/3 分組 |
| E03 | 3+ Groups，含合法同 Path 重複 Tabs | 以 group / multiset 驗證，不去重 |
| E04 | Snapshot 內有不存在的 fixture 路徑 | Task-2 後應 warning + skip，其他合法 path 繼續 |
| E05 | 可控延遲／暫時偵測問題 | Issue-2 後應成功且只送一次 Invoke |
| E06 | 真正多候選／外部同時操作 | Issue-2 後保守停止，既有 tabs 不被改動 |
| E07 | Partial failure 後指定 Group / ItemIndexes 補做 | Issue-2 後不整組重做、stale target 被拒絕 |

**不要靠在真實桌面隨機狂開／關 Tabs 重現競態。** 競態負面路徑首先靠 Unit 的 observation injection 保證；E2E 用受控情境與目視交叉驗證。焦點變化可以記錄供 Feature Request-1 參考，但不是目前 Task-1 的「背景還原成功」證明。

## 8. Pester 與測試 runner 的設計

### 8.1 Pester 版本政策

- 建議以 **Pester 5.x** 作為唯一正式 test API（`PesterConfiguration`、tags、mock、test result export），固定一個實測可用的 5.x 版本；**不是**使用系統內建的 Pester 3.4.0 然後假設其語法相容。
- 此次裝置目前**沒有列到 Pester 5.x**。依公司環境政策，由維護者明確提供／安裝所選版本；測試程式本身**不執行** `Install-Module`、不修改 Execution Policy、不偷偷覆蓋系統模組。
- 如果公司環境無法提供 Pester 5，先標記 `Blocked: Pester 5 unavailable`；可另評估首批用 3.4 相容語法，但必須選定**一個**正式 API，不維護兩套分歧測試。
- **支援政策更新（2026-11-02）**：E2E 主要鎖定 **Windows 上的 PowerShell 7（`pwsh.exe`，STA）**；Windows PowerShell 5.1 不再是產品支援或 CI 驗收條件。PowerShell 7 的 Unit Tests 不能代替實際 Shell COM／UIA／Explorer Tabs E2E 驗收。以上為後續計畫的最新版政策；本文件早期 5.1／Pester 環境調查仍作歷史紀錄。

### 8.2 Runner 的介面（需先實作）

~~~powershell
# 安全預設：只跑 Unit，不開 Explorer
pwsh.exe -NoProfile -NonInteractive -File .\tests\Invoke-Tests.ps1 -Suite Unit

# 僅於專用、互動式 Windows 11 session 手動執行
pwsh.exe -NoProfile -Sta -File .\tests\Invoke-Tests.ps1 `
    -Suite Integration -AllowExplorerUiChanges
~~~

`tests/Invoke-Tests.ps1` 的約定：

1. `-Suite` 預設為 `Unit`，不會在未指定的情況下掃描整棵 `tests/` 並順便跑 Integration。
2. `-Suite Integration` 一定還要 `-AllowExplorerUiChanges`，通過嚴格 preflight 後才可進入測試主體；缺少條件應拒絕並輸出阻擋原因。
3. Runner 明確檢查 Pester major version。對 Pester 5 可以採用 `[PesterConfiguration]::Default`、`Run.Path`、`Filter.Tag`、`Run.PassThru` 和 `TestResult`，避免把 3.4 的 `Invoke-Pester` 參數誤當成 5.x。
4. `FailedCount > 0`、`TotalCount = 0`、測試框架缺失等情況，須傳回**非零 process exit code**。Test discovery 0 cases 絕不可被認為成功。
5. 對未執行的 E2E 清楚標記 `NotRun`；環境不合格標記 `Blocked`；只有真正完成斷言才可標記 `Passed`。
6. 顯示可機器讀取的測試摘要，包含 PowerShell/Pester 版本、suite、passed/failed/skipped 與 E2E 是否真正執行；不把 `Write-Host "Passed"` 當作唯一證據。

建議狀態格式（**示意，非已取得之測試結果**）：

~~~text
Unit: Passed (S01-S10, V01-V08)
Integration E01: NotRun (requires isolated interactive Windows session)
Issue-2 R-cases: Pending implementation
~~~

### 8.3 Pester 測試示意

以下為**提議的 API / 測試形狀，不是目前可直接執行的測試**；需要先按第 4 節抽出 module。

~~~powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\ResumeExplorer.psm1') -Force
}

Describe 'Snapshot v1 validation' -Tag 'Unit' {
    It 'rejects unsupported versions before Explorer side effects' {
        $file = Join-Path $TestDrive 'unsupported.json'
        [IO.File]::WriteAllText(
            $file,
            '{"Version":2,"CapturedAt":"2026-11-01T07:00:00-08:00","Windows":[]}',
            (New-Object System.Text.UTF8Encoding($false))
        )

        { Read-SnapshotFile -Path $file } | Should -Throw '*Unsupported*'
        # 另一個 orchestration test 應另外斷言 UI adapter 調用次數全部為 0。
    }
}
~~~

**重要**：Mock 的目標是 module 內部真正呼叫的 adapter；若 mock 沒有生效，unit runner 必須 fail closed，而不是默默回退到真實 Shell COM／Explorer。可用針對 forbidden side effects 的 spy / throw-on-call adapter 證明隔離成功。

### 8.4 CI 與測試覆蓋

- 可選擇 Windows CI runner（或公司內部 Windows pipeline），**自動只跑 Unit**。一般 CI runner 不能保證正確互動式 Explorer session，故不進行 GUI E2E。
- 單元測試不得依賴已存在的真實 Snapshot、已開啟的 Explorer 或特定使用者目錄；以合成觀測與臨時資料夾作為唯一 fixture。
- 產生 NUnit/JUnit XML 或其他 pipeline 可讀的報告；`tests` 輸出的含路徑 JSON 與診斷 log 不提交到 Git，分享前先去識別化。
- Coverage 優先針對 Snapshot、Group planning 與 candidate resolution 的純邏輯。初期不需要為了追求單一覆蓋率數字而硬 mock 複雜 UIA；**分支行為、安全不變條件和 E2E smoke 才是發布依據**。
- CI 不應只因所有 E2E 都被 Skip 就宣稱「全部端對端成功」；Unit 與 E2E 的狀態必須分開報告。

## 9. 建議的迭代順序與可交付成果

| 階段 | 內容 | 交付／Exit gate |
| --- | --- | --- |
| A. 安全測試入口 | 選定 Pester 5.x 來源；拆薄 CLI；新增 module 和 Unit-only runner | S01 通過；import 0 side effects |
| B. 快速 Snapshot 回歸 | 先完成 S02–S10，使用獨立 snapshot + 合成 COM views | Capture/JSON/Preview 基本行為可自動回歸 |
| C. **E2E 第一條金線** | 在隔離 Win11 session 建立 E01：2 Windows / 3 Tabs | 真實視窗分組被獨立觀測和人眼確認 |
| D. Schema 與 Task-2 | 完成 V01–V10；不存在 Path warning + skip 且不失索引 | 資料異常不會造成無法追蹤的部分恢復 |
| E. Issue-2 決策安全 | 隨 Issue-2 實作加上 R01–R18 的對應 tests | 不重複 Invoke、不猜 Tab、能記錄 partial failure |
| F. 測試整合與說明 | Test result、README 測試命令、Backlog/commit references、選用 CI | 有可重現的單元與 E2E 證據 |

**推薦節奏**：A → B 的 6–10 個核心 case → **C（E01）** → D → E → F。不要先實作幾十個低風險序列化邊角案例，卻一直沒有真實 Explorer 分組驗收。

若 Issue-2 開發先行，則在 E 階段遵循「某一安全修復的 production code 與對應 R-case 同 PR」的原則，而不是等全部實作後才補測試。

### 9.1 依賴分割：Task-1 何時可以完成

Task-1 可以在**測試基礎、Snapshot 必要 cases、基本 Restore side-effect guards，以及 E01 smoke test 可重複執行且通過**後標記基建完成。

**不要求** Issue-2 的所有 R-cases 必須先通過才能關閉 Task-1；那些 cases 依其功能實作進度持續納入後續 PR 的回歸門檻。Task-2 的 V04/V05/V10 也是對應功能修復後才轉綠。這樣不會不合理地把「建立測試系統」阻塞在其他功能項目的整體交付上。

### 9.2 應提交的檔案

1. `src/ResumeExplorer.psm1` 與維持 CLI 相容的 `resume-explorer.ps1`。
2. `tests/Invoke-Tests.ps1`、`tests/Unit/*.Tests.ps1`、必要的 fixtures / safety adapter。
3. `tests/Integration/Explorer.Smoke.Tests.ps1` 及 preflight／人工作業說明。
4. 第一次 Unit 及 E01 的測試執行證據：執行日期、環境、斷言結果、失敗摘要（路徑經匿名化）。
5. README 增加安裝前置條件與執行命令；Backlog 記錄對應 commit、已通過範圍和暫不支援事項。

## 10. Definition of Done（Task-1）

- [ ] Pester 的正式版本與來源明確，缺失／錯 major version 時 runner fail closed。
- [ ] Import module 完全沒有 Action、COM/UIA 或 Explorer 副作用。
- [ ] Unit 使用隔離測試檔；預設 Snapshot 不變；不開／關任何真實 Explorer。
- [ ] Snapshot 版本、非法 JSON、結構驗證、空資料、單元素 array、重複路徑、UTF-8 roundtrip 等首批測試通過。
- [ ] Restore 的呼叫點可被 mock；能以 synthetic identity / observation 驗證 Invoke／Navigate 的目標與次數。
- [ ] E01 在**獨立互動式 Windows 11 session** 實測通過：確實額外新增 2 Windows / 3 Tabs，且分組正確。
- [ ] E2E 未啟用／preflight fail 時明確 NotRun/Blocked，未發生任何 UI side effects。
- [ ] CLI Capture/Preview/Restore 與 Snapshot v1 的既有契約未破壞。
- [ ] Test runner 對錯誤與零執行案例回傳非零 exit code；Unit / E2E status 分離。
- [ ] README 有執行方法、OS／PowerShell／Pester 版本、E2E 人工安全守則與限制。
- [ ] 沒有引入 SendKeys、Clipboard、kill/restart Explorer、Registry 或 Execution Policy 修改。
- [ ] Issue-2／Task-2 的尚未落地案例被正確標記 Pending，而不是算 Passed 或悄悄忽略。

## 11. 方案取捨與風險

| 做法 | 判定 | 理由 |
| --- | --- | --- |
| 原 151 行程式直接 dot-source 來測 | 不採用 | Action dispatch 會觸發預設 Preview，安全性差 |
| 只測 `Read-Snapshot` / `ConvertTo-Json` | 不足 | 無法驗證 COM/UIA/timing 與分組 |
| 為測試全面重寫成大型 object framework | 不採用 | 超出小工具的成本與回歸風險 |
| 一個 module + 薄 CLI + 可 mock adapter | **採用** | 最小侵入、容易接 Pester |
| 每次 CI 都啟動真實 Explorer E2E | 不採用 | GUI session 不確定，會污染桌面 |
| E2E opt-in + 隔離 session + preflight | **採用** | 限制副作用並保留真實驗證 |
| E2E 失敗就 kill Explorer 清理 | 嚴禁 | 可能破壞正在使用的視窗與未儲存工作 |
| 只依 console 的 `Requested new tab` 判成功 | 不採用 | 「發出請求」不是「正確完成」 |
| 重複路徑全部去重 | 不採用 | 破壞合法的多 tab 要求 |

### 11.1 尚未解決的驗證風險

- Windows Explorer Tab 的 COM identity、UIA control hierarchy 與 HWND grouping 都可能隨 Windows build 改變。Unit 無法證明真實環境可用，故必須保留 E2E gate 與環境資訊。
- 對 Shell COM / UIA 的單次同步呼叫若卡住，fake-clock 的 polling deadline 不是嚴格的整體 wall-clock timeout；不得宣稱 Unit 模擬已解決此問題。
- CI 可以可靠保護純邏輯、編排與禁止副作用的契約，無法替代 Horizon VDI 的實際行為測試。
- 失敗報告若只保存錯誤字串，將不利於 Issue-2 的 item-level retry；測試應推動 machine-readable 狀態，但不要因此提前加入不必要的 GUI 功能。

## 12. 參考

本次查閱：`resume-explorer.ps1`、`Backlog.md`、`README.md`、`resume-explorer-Issue-2-fix-plan.md`、Git commit `dd179de`；先前迭代的 Automated tests 建議。

Pester 官方：

- Pester v5 configuration：<https://pester.dev/docs/v5/usage/Configuration>
- Pester v5 Invoke-Pester：<https://pester.dev/docs/v5/commands/Invoke-Pester>
- Pester v5 mocking：<https://pester.dev/docs/v5/usage/mocking>

**狀態聲明：**本文件只提供設計／實作計畫。尚未新增或執行測試、未安裝 Pester 5、未實際執行 Capture/Restore，也未修改任何產品行為。
