# Task-5 — PowerShell 7 / Windows Explorer E2E Smoke Test：調查與實作計畫

- **建立日期：** 2026-11-02
- **狀態：** Proposed / **Plan only；尚未實作 E2E runner，也未執行真實 Explorer E2E**
- **優先級：** P1（PowerShell 7-only Runtime Support 的實際 GUI／COM 驗收關卡）
- **對應：** [Backlog / Tasks](../Backlog.md) 的 Task-5；[Task-1 Automated Tests Plan](resume-explorer-Task-1-automated-tests-plan.md)
- **測試對象：** Windows 11 + `pwsh.exe` 7.x + 真實 Explorer Tabs；不再要求 Windows PowerShell 5.1
- **範圍原則：** 先證明現有 CLI 行為；只在有可重現缺陷證據後，另案進行最小 production 修復

## 1. 決策摘要與目標

**Approve：應優先建立小型、明確 opt-in 的 PowerShell 7 真實 Explorer E2E Smoke Test。**
取消 PS5.1 正式支援後，`pwsh` 下的 Unit Pass 不等於 Windows Shell COM、.NET UI Automation 與可見 Tabs 已在真實 Explorer 上通過。這是測試／發布信心的缺口，不是已證實的 PowerShell 7 相容性缺陷。

本 Task 聚焦下列三項端對端契約：

1. **Shell COM / UIA 基礎互通**：在 `pwsh -Sta` 的專用互動式 Windows Session，`Shell.Application.Windows()` 可以可靠列舉 Explorer Tabs；`UIAutomationClient` 可以取得目標 Window 的 `AddButton` / `InvokePattern`。
2. **E01 Capture → Preview → Restore → Verify**：兩個原始測試視窗、合計三個 Tabs（`A|B`、`C`）被擷取為兩組／三項；Restore **另外建立**兩個可見測試視窗，含相同分組與路徑，原 fixture 不被改動。
3. **E02 Retry 真實成功路徑**：用**獨立的測試 Snapshot**，先讓一個缺失的測試路徑得到 `SkippedInvalidPath`，之後建立該路徑，以 `PreviewRetry` 明確選擇測試 HWND、Group/Item，驗證真正建立一個新 Tab 並導覽成功。原 Report 不得手動改寫或用 Path-only 猜選目標。

**不是本 Task 的目標**：實作 `Restart`、免焦點操作、修復 Issue-4 同步 Hang、清理多餘 Explorer Process、改變 Snapshot／Report Schema、引入新的測試架構或保證跨 Windows Build 全面相容。

## 2. Evidence first：2026-11-02 版本現況

| 證據來源 | 已確認事實 | 尚未證明 |
| --- | --- | --- |
| `resume-explorer.ps1` | 入口 Action 為 `Capture`、`Preview`、`Restore`、`PreviewRetry`、`Retry`；dot-source 無 Action 的 `resume-explorer.core.ps1` | 在真實 PS7 Explorer 上各 Action 都可成功 |
| `resume-explorer.core.ps1` | `Get-ExplorerObservation` 使用 `Shell.Application` / COM identity；`Get-NewTabInvokePattern` 使用 UIA `AddButton`；`OpenWindow` 要求 `-WindowStyle Normal` | PS7 + VDI 的 UIA Control 可用、可見性與分頁群組正確 |
| `Save-Snapshot` | Capture **全域列舉可辨識的 Explorer 資料夾 Tabs**，依 RawHwnd 分組 | 混入非測試窗口時無法安全只擷取測試資料 |
| `Invoke-RestoreGroups` | 首項建立 Window；其餘項目透過一次 Invoke/Navigate；不存在 Path 標 `SkippedInvalidPath` | 真實 Explorer 上的 identity verification 與畫面一致 |
| `Show-RetryPreview` / `Start-RetryRun` | PreviewRetry **寫入 sidecar**；Retry 校驗 Report hash、Target fingerprint、family child 與 status，並建立 child Report | 真實 Retry 的安全目標選擇及補做後的 Tab 狀態 |
| 本次只讀 Runtime Probe | Windows `pwsh` **7.6.1 / STA** 可載入 `UIAutomationClient`、`UIAutomationTypes`（並解析 `AutomationElement` type） | 沒有執行 Shell COM enumeration、UIA element search 或 GUI E2E |
| 本次離線回歸 | `Issue2.Tests.ps1` **39/39**、`RestoreSummary.Tests.ps1` **17/17**，各 Exit 0，沒有真實 Explorer 操作 | 不可作為 E01／E02 Passed |
| Task-1 歷史計畫 | 已提出隔離互動式 session、E01、Pester runner | 文中部分「尚無 tests / 單檔 CLI」是當時歷史狀態；現已有 core + tests，不可照抄舊的架構重構提案 |

**證據與假設分離**：PS7 的 managed UIAutomation assemblies 能載入，**不代表** Explorer 的 AddButton 可被找到或 Invoke 成功；原 beta 的人工 2/3 記錄也不能代替此版本、此 PS7 host 的 E2E。

## 3. 與既有工作的關係／非目標

- **Task-1（P1）**：整體測試基礎建設、Unit／Integration 自動化、可選 Pester 5。**Task-5 是其 PS7 真實互通的最小驗收工作**，應先以目前 Core + 原生腳本建立可重複 smoke，不必等待 Pester 5、Module 重新抽取或完整測試框架。之後可併入 Task-1 runner。
- **Task-3（P2）**：CLI Single-Instance Guard。Task-5 的 UI smoke 不需等待 Lock 實作；若 Task-3 先實作，smoke 必須依其鎖規則**序列執行**，不能藉測試繞過全域 Lock。
- **Issue-3（P2）**：焦點獨立問題；本 smoke 只紀錄焦點，不以不搶焦點作為 E01／E02 成功條件。
- **Issue-4（P1）**：同步 COM/UIA 呼叫可能超過輪詢期限。若 E2E 觀測到阻塞，保留診斷並轉 Issue-4 RCA；不得把現有輪詢 timeout 說成 hard wall-clock timeout。
- **Task-2**：不存在路徑的 warning/skip UX 尚待獨立驗收。E02 僅依現有 `SkippedInvalidPath` status 建立安全補做 fixture，**不代表 Task-2 所有 warning 要求已完成**。
- **PS 5.1**：已有的歷史測試結果可保留，但不再是本 Task Gate。

## 4. 不可妥協的安全限制

1. **絕不在目前工作中的 Explorer／VMware Horizon 工作階段執行真實 E2E。** 使用可重設 Windows 11 VM／VDI 測試環境，最好另設專用 Windows 測試使用者；須由使用者明確允許 GUI 副作用。一般 Remote Desktop Commander 背景命令、headless CI、Session 0 不算合格互動桌面。
2. **預設零 GUI 副作用**：Unit、`-Mode Preflight`、Test Discovery、CI、腳本 import、未附 `-AllowExplorerUiChanges` 的執行，不能開／關 Explorer 或 Navigate；失敗應 `Blocked`／`NotRun`，不可繞過。
3. **Capture 是全域的**：即使只打算比對 fixture paths，仍可能把其他使用者 Explorer 視窗寫進 Snapshot 並在 Restore 時重複建立。因此 E01 Capture 前必須**確認當前 Shell enumeration 僅有預期 fixture windows/tabs**；出現未知 HWND、Path、identity、讀取不完整或其他會影響 scope 的窗口，一律拒絕 Capture/Restore。
4. 每次測試使用唯一 `%TEMP%\ResumeExplorer-E2E-<GUID>`；其中分別存 `capture.json`、`restore-root.json`、`retry-fixture.json`、`retry-root.json`、`RetryRuns`、sidecar 與 smoke 結果。**不得使用或覆寫預設 Snapshot 與正式 `%LOCALAPPDATA%\ResumeExplorer\Runs`**。
5. **不使用** `taskkill`／Restart Explorer／`Stop-Process explorer`、全域 SendKeys、Clipboard、Registry、ExecutionPolicy Bypass，或對不明 HWND 進行導航。驗證不明時 **fail closed**；不自動重跑 Restore/Retry。
6. Snapshot／Report／sidecar 保留原始、未改動的證據；特別是 `OutcomeUnknown` 項目不可因測試 convenience 而自動補做或加 `-IncludeUncertain`。E02 選用零副作用來源的 `SkippedInvalidPath`。
7. Runner 不應以偽造 fixture 冒充真實成功；測試完只能在人工確認 HWND 都屬於測試 fixture 後**手動**關閉那些測試窗口。任何不確定的視窗不得關閉；不自動清除失敗證據。
8. 若有阻塞的同步 COM/UIA 呼叫，**不得為「超時」而 kill Explorer 或強制終止不屬於本輪的 Process**。記錄無 hard timeout 的限制，在隔離 VM 中人工介入復原。

## 5. 最小實作架構（不動 Production 初始行為）

**優先採用「獨立、安全 gated 的 smoke harness + 既有 CLI」**，而非先重構 Core 或引入 Pester 硬依賴。

候選檔案（**本次規劃未建立**）：

```text
tests/
  Integration/
    Invoke-ExplorerSmoke.ps1        # explicit Preflight / E01 / E02，預設只讀
    README.md                       # 專用桌面與人工操作 SOP
    # 小型 read-only observer/helper 可按需求加入
plans/
  resume-explorer-Task-5-powershell7-explorer-e2e-smoke-plan.md
```

- Runner 直接以獨立 `pwsh.exe -NoProfile -Sta -File .\resume-explorer.ps1 ...` 呼叫**真實公開 CLI**。不透過 mock 假扮成功，不用修改/覆寫產品函式或在 Production CLI 開 debug bypass 參數。
- `Preflight` 與一般執行時，Runner **不建立 fixture Explorer**；`-Case E01/E02 -AllowExplorerUiChanges` 另需驗證獨立環境、操作者確認及 fixture ownership。
- 安全 gate 必須在**所有 Explorer GUI 副作用前**執行；分離 `CanUseShellCOM`、`CanUseUIA`、`ValidateIsolatedSession`、`ValidateFixtureScope` 等最小 helpers。不為測試把 Registry/ExecutionPolicy 設定當作解法。
- 即使操作者提供 `-ConfirmIsolatedSession`，也不能單靠 flag 宣稱隔離已驗證；程序應檢查 OS、PS7、STA、實際 GUI session、Explorer 觀測是否完整，以及測試窗口是否可歸屬。任何無法確實自動驗證的條件要求人工作業／證據，不能靜默放行。
- **初期允許手動建立 fixture + 腳本只執行觀測／斷言**；隨後再加入明確 opt-in 的 fixture window 建立流程。目的在於儘早發現 PS7/COM/UIA 問題，而非先完成龐大的 orchestration。
- 用 `try/finally` 確保測試日誌／結果可保存；**不**在 `finally` 自動關閉 Explorer。遇 `Incomplete`、`OutcomeUnknown` 或未辨識 Window 時停止對該 fixture 的後續副作用。

### 5.1 Preflight 的必檢欄位

| 分類 | Gate | 不通過時 |
| --- | --- | --- |
| Runtime | Windows 11；`$PSVersionTable.PSEdition` 為 Core、Major=7；執行在 STA | `Blocked: RuntimeUnsupported` |
| Host / Session | 專用互動式登入使用者工作階段；不是 Session 0/headless；能安全觀測互動 desktop；人工確認環境獨立 | `Blocked: SessionNotIsolated` |
| COM / UIA | `Shell.Application` 只讀列舉可信；`UIAutomationClient`／`UIAutomationTypes` 可載入；實際 AddButton 是否可取得於 fixture 階段再驗證 | `Blocked: ShellOrUiaUnavailable` |
| Scope | Capture 前 Explorer 的可辨識窗口/Tab 全屬 fixture，且 identity/Path 完整、數目符合預期 | `Blocked: ForeignOrAmbiguousExplorer` |
| Paths | RunId 唯一且測試根目錄新建；來源 Snapshot/Report 為唯一新路徑；B 缺失的 precondition 經驗證 | `Blocked: UnsafeFixture` |
| Consent | 測試模式與 GUI side-effect 授權皆明確；沒有隱含自動執行 | `NotRun: NotAuthorized` |

**重要**：測試 Runner 也可能自身卡在 COM read；只能在隔離桌面測試，不能宣稱「Preflight 一定在 N 秒內返回」。

## 6. 詳細測試路徑

### E00 — 離線基線（可在一般 dev / CI 執行）

```powershell
pwsh.exe -NoProfile -NonInteractive -File .\tests\Issue2.Tests.ps1
pwsh.exe -NoProfile -NonInteractive -File .\tests\RestoreSummary.Tests.ps1
```

- 記錄 PowerShell 版本、每套 PASS 數與 ExitCode，預期現有數量 **39** / **17**。
- 確認無真實 Explorer 操作。這兩套是 **Unit/adapter baseline**，E2E 欄位仍為 `NotRun`。
- 不修改既有 tests 來適應 Smoke；若發現問題，先 RCA。

### E01 — 真實 2 Windows / 3 Tabs Capture + Restore

獨立 VM／Test Account 的 fixture（`A`、`B`、`C` 都是本輪建立且存在的資料夾）：

```text
TestRoot\
  E01\
    A\
    B\
    C\
    capture.json           # 由真實 Capture 寫入
    restore-root.json      # 由真實 Restore 寫入
原 Window 1: A | B
原 Window 2: C
```

1. **先完成 Preflight**，由操作者建立兩個 fixture Explorer windows。記錄 Window Root/Raw HWND、PID、SessionId、Tab identity、Path 與可見性；先確認該 desktop 沒有非 fixture 的 Explorer 視窗。
2. 用 `-Action Capture -Snapshot <TestRoot>\E01\capture.json` 執行正式 CLI；解析 Snapshot v1：`Windows.Count=2`、Paths 總數=3，兩組 path multiset 為 `{A,B}` 與 `{C}`（不依賴 Group 的順序，也不以 `-Unique` 消除重複）。
3. 用 `-Action Preview` 讀**同一個明確指定的 Snapshot**，所有 fixture 路徑皆存在且沒有非 fixture 路徑。Preview 不建立任何 Window。
4. 保存 Restore 前的完整 baseline；用 `-Action Restore -Snapshot <capture.json> -ReportPath <restore-root.json>` 執行，**不能重用 ReportPath**。
5. 解析 JSON：`SchemaVersion=1`、`State=Completed`、原始 Group/Item 索引仍可追蹤；預期 **3/3 Verified**。但 Report 成功**不等於**可見 GUI 成功。
6. 透過與 production 不完全共用的**獨立 observer / UIA 檢查**加上操作者目視，驗證新增**兩個可見 Root windows／三個 Tabs**，一組實際包含 A、B，另一組包含 C；新增視窗的 identity/HWND 與原窗口不同，原 fixture 的 Tab identity／Path／Grouping 未被改動。
7. 若有歧義、Window 不可見、路徑錯誤或 timeout，標 `Failed`，**保留報告與畫面證據、停止本輪**；不要自動重跑 Restore 造成重複窗口。人工清理 fixture 後才可用**新的 RunId**重試。

此項不要求 Tab 順序、focus、window placement 或無干擾 UI（屬獨立功能需求），但**必須實際可見且分組正確**。

### E02 — 真實 Retry：SkippedInvalidPath → PreviewRetry → Retry

**使用另一個乾淨的 fixture／RunId；先人工關閉 E01 測試窗口並重新 Preflight。** 不將 E01 報告修改為有「失敗」項目。

1. 在 `TestRoot\E02\` 建立存在的 `A` 資料夾，確認 `B` **尚不存在**。直接建立**獨立且合法的 Snapshot v1**：`Windows=[{Paths:[A,B]}]`，不修改 E01 Capture Snapshot、不偽造 Report。
2. 使用 `pwsh -Sta` 的正式 CLI `Restore`，指定 `-Snapshot <retry-fixture.json> -ReportPath <retry-root.json>`。預期第一項 A 建立**可見測試新 Window**且 `Verified`；第二項 B 因資料夾不存在為 `SkippedInvalidPath`，`InvokeAttempted/NavigateAttempted/WindowCreateAttempted` 都不是 true。這是刻意的 fixture 前提，不是為了重現 COM 錯誤。
3. 記錄此 Window 的 Raw HWND、Root HWND、fingerprint 與所有 Tabs；確認沒有不明來源的新窗口。**此時再建立 B 資料夾**，且保持來源 Snapshot 與 `retry-root.json` 完全不變（保存 SHA-256）。
4. 執行 `-Action PreviewRetry -ReportPath <retry-root.json>`：它會建立 `retry-root.json.retry-preview.json`（正常預期 sidecar）；從其中取得**真正屬於測試 A Window** 的 `Targets[].Hwnd`。禁止使用任意 HWND、Path-only 或 UI 最前景窗口猜選。
5. 僅在 fingerprint、RunId、ReportHash、target HWND 皆吻合時，以 `-Action Retry -ReportPath <retry-root.json> -GroupIndex 1 -ItemIndexes 2 -TargetHwnd <FixtureHwnd>` 明確補做；**不加 `-IncludeUncertain`**。
6. 驗證新 child Report 位於 `RetryRuns\`，只含原 ItemIndex=2 的一項、`State=Completed`、`Status=Verified`，Parent/Root 關係正確；parent report bytes/hash 不變。原 A Window **只增加 B 一個 Tab**，其身分及導覽路徑可由 GUI/observer 獨立確認；A 原 Tab 不被導航或刪改。
7. 完成後標記 E02 `Passed`。如果任何步驟出現 `OutcomeUnknown`、來源 Report 變更、Window 不可辨識或目標 fingerprint stale，**停止，保存診斷，不自行補做**。其餘負向的「拒絕二次 Replay／拒絕 stale HWND／Unknown 須 IncludeUncertain」優先由既有 deterministic Unit 驗證，不用在真實桌面刻意製造危險競態。

**為什麼這個案例安全且可實作**：目前 `Invoke-RestoreGroups` 會略過不存在的 B，且留下 `SkippedInvalidPath`；`Select-RetryItems` 允許尚未嘗試的項目補做；`PreviewRetry` 取得實際 fingerprint，`Retry` 會對指定現存窗口建立新 Tab。因此無須修改 Report Schema、繞過 identity 驗證或假造失敗。

## 7. Matrix / Acceptance Evidence

| ID | 測試 | 主要驗證 | 分類 |
| --- | --- | --- | --- |
| T5-00 | PS7 STA / UIAutomation assembly load | 版本、Thread apartment、assembly 載入 | 已完成 read-only runtime probe；非 E2E |
| T5-01 | Offline 39+17 | Exit 0、無 Explorer 副作用 | 已完成本輪回歸；非 E2E |
| T5-02 | 不加授權或非互動 Session | `NotRun/Blocked`、無 Explorer GUI 副作用 | Runner 待實作 |
| T5-03 | 外來 Explorer HWND、觀測不可信 | Preflight fail closed，拒絕 Capture/Restore | Runner 待實作 |
| T5-04 | PS7 真實 Shell COM/UIA | 正確讀取 Tabs、可找到 AddButton；不混淆 Raw/Root HWND | 未執行 |
| T5-05 | E01 Capture / Preview | 2 Groups、3 Paths、預覽無修改 | 未執行 |
| T5-06 | E01 Restore + 獨立觀測 | 新增 2 可見 Windows、3 Tabs、3/3 Verified；原 fixture 不變 | 未執行 |
| T5-07 | E02 第一次 Restore | A Verified、B SkippedInvalidPath、B 沒有建立嘗試 | 未執行 |
| T5-08 | E02 PreviewRetry + Retry | 指定 HWND/Item2、child 1/1 Verified、B 增加在 A Window | 未執行 |
| T5-09 | Retry family/report integrity | parent hash 不變、child linking／fingerprint 正確 | 未執行 |
| T5-10 | Fail/abort & no auto replay | 不猜候選、不重複 Navigate/Invoke、保存不明結果 | Unit 已部分覆蓋；GUI 例外路徑非預設 smoke |
| T5-11 | Windows Build/VDI 環境註記 | 版本、Session、observer、實際畫面結果 | 未執行 |

判定規則：`Passed` 只授予**實際執行且所有必需斷言成功**的 case；`Blocked` 表示環境／授權不足；`NotRun` 表示未執行；`Failed` 表示已執行但驗證不符。要求 E2E 時若測試未執行，**不可回傳成功 Exit Code 或宣稱 Passed**。Unit Passed 不會自動讓 E01/E02 綠燈。

## 8. 分階段開發／驗收／回退

| Phase | 實作事項 | Exit Gate |
| --- | --- | --- |
| **0. Baseline** | 核對 Git、core/CLI、安全契約、PS7 版本；重跑 `Issue2`／`RestoreSummary`，記錄 OS/STA/UIA load | 39/39、17/17；0 GUI 操作，保留現有 tests |
| **1. Safety-first preflight** | 新增獨立 `tests/Integration/Invoke-ExplorerSmoke.ps1`／README：預設唯讀、PS7+STA+interactive+isolated gate、fixture ownership、唯一 RunId、Blocked/NotRun | 不授權／錯 session／混入未知視窗時無 Capture/Restore/Retry；非零退出或明確 NotRun |
| **2. E01 Capture/Restore** | 可先手動 fixture，使用真實 CLI；Snapshot/Report 斷言 + 不同路徑 observer + 人工可見性確認 | T5-04～06 在受控桌面實際 Passed |
| **3. E02 Retry** | 獨立 A+缺失 B fixture、報告 hash/sidecar/child 驗證、正確 HWND 選擇 | T5-07～09 在受控桌面實際 Passed |
| **4. Harden & document** | 偵測誤判／不明狀態時 fail closed；輸出可機器讀取的 smoke 結果，更新 README/Task-1/Backlog，補必要 regression | 所有 E2E gate 可重複、不可被 CI 意外觸發；可追蹤證據 |
| **5. Conditional production fix（獨立 Issue）** | 只有 PS7 真實測試找到可重現產品缺陷，先 RCA + deterministic regression，再做最小修復 | CLI、安全不變條件、Report/Snapshot Schema 無不必要 breaking change |

- **最短路徑**：Phase 0 → 1 → 2 的手動可觀測驗證 → 3 → 4。**不以 Pester 5 或 Module 重構作為先決條件**；Task-1 完整測試架構可在後續整合。
- **Release Gate**：正式將 PS7-only 視為經過 GUI 實證的支援政策，至少須 E01/E02 在指定受支援 Win11/PS7 組合 Passed；其他未測 Windows Build、PS7 minor / VDI 版本僅能標 `NotRun`，不能聲稱普遍相容。
- **Failure handling**：先停止本 fixture 操作；保留 RunId、OS/PS/Session、stdout/stderr、CLI exit、Snapshot/Report/sidecar、HWND/identity/路徑（必要時脫敏）與 GUI 目視結果；**不得無條件重試或清理 Explorer**。發現對現有主流程的相容性缺陷，另建 Issue、定義 regression，再修復。
- **Commit / Version**：本次只寫計畫，不修改 production、現有測試或版本，也不自動 commit。日後實作測試 harness 可做獨立 commit；只有必要的產品行為改變才評估版本升級。

## 9. Definition of Done

- [ ] E2E harness 具有安全的唯讀預設與顯式 GUI opt-in；Unit／CI／import 不能意外啟動 Explorer。
- [ ] 在**獨立、真正互動式**的 Windows 11 測試桌面，確認 PS7 STA、Shell COM observation、UIA AddButton 可用；完整記錄 Windows Build/PS7 版本。
- [ ] Capture 全域 scope preflight 通過；未知視窗、觀測不可信時拒絕，絕不把使用中視窗還原到測試結果。
- [ ] E01：Capture / Preview 得到 2 組 3 Paths；Restore 另外建立**可見** 2 Windows／3 Tabs，3/3 Verified，原 fixture 不變；獨立觀測及人工核對。
- [ ] E02：以真實 `SkippedInvalidPath` 報告為基礎，對 test-owned HWND 補做 Item 2，child 1/1 Verified、原 report hash 不變、原 A Tab 不變且只新增 B。
- [ ] GUI 失敗、歧義、硬體／VDI 限制有 `Failed/Blocked/NotRun` 與足夠 evidence；不自動重跑 Restore／Retry。
- [ ] 現有 39+17 deterministic tests 維持通過；不得為「過測」削弱原斷言。
- [ ] 無真實 Explorer 強制終止、Restart、Registry/ExecutionPolicy 改動、跨 repo 變更或自動清理未知窗口。
- [ ] README、Backlog、Task-1 cross-reference 與實測結果同步；E2E 不能在沒有真實 GUI 證據時標記 Completed。

## 10. 重要風險／應對

1. **PS7 COM/UIA assembly 可載入但真實 Explorer 不支援或 UI 控制項變動**：保留錯誤階段與 HRESULT／UIA tree 觀察；不隨意 fallback 到 Windows PowerShell 5.1，也不以 path-only 放寬安全規則。
2. **Explorer / Google DriveFS / VDI 負載導致同步呼叫 Hang**：本 smoke 先在乾淨測試桌面；同步阻塞轉 Issue-4 調查。輪詢 deadline 不等於全流程 wall-clock 保證。
3. **同路徑其他 Explorer Windows 造成候選歧義**：環境及 fixture scope 嚴格預檢；比對 HWND、RootHwnd、PID/StartTime、identity，不靠 Path-only。
4. **Snapshot Capture 全域收集**：只接受僅有 fixture windows 的 session；不要在真實桌面「擷取後只篩測試路徑」。
5. **E02 測試可能留下 partial session**：任何非預期結果停在第一個不確定點，不再 Retry；人工確認視窗屬測試窗口後清理。
6. **自動測試擴張成本**：首輪真實 smoke **不要求** Pester 5 或先改 production 架構；將測試 Runner 留在 `tests/Integration`，維持 CLI 相容。

## 11. 參考

- [README](../README.md)：正式 PowerShell 7-only 政策、Restore/Retry 使用與安全限制。
- [Backlog](../Backlog.md)：Task-1、Task-3、Issue-3/4、Task-5 與 Runtime Policy。
- [Task-1 Automated Tests Plan](resume-explorer-Task-1-automated-tests-plan.md)：較完整的 Unit／Pester／E2E 基建；含早期已過時的 repo 現況，須以本計畫的實際 Source Review 為準。
- `resume-explorer.ps1` / `resume-explorer.core.ps1`：當前具體行為及 Snapshot/Report/Retry 不變條件。
- `tests/Issue2.Tests.ps1` / `tests/RestoreSummary.Tests.ps1`：現有 deterministic regression。

**狀態聲明：**本次工作僅完成 Review 與 Markdown 規劃；未建置 harness、未呼叫真實 Explorer COM/UIA API 或執行 Capture/Restore/Retry 的 E2E。
