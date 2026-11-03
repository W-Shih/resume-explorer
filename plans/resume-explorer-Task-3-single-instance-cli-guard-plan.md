# Task-3 — Single-Instance CLI Guard：Review 與詳細實作計畫

- **Review 日期：** 2026-11-02
- **優先級：** P2；先完成 [Task-4 S16 測試基線修復](resume-explorer-Task-4-restore-summary-s16-regression-plan.md) 後，建議作為下一個獨立實作；FR-6 Phase 3/4 的必要前置
- **狀態：** **Reviewed / Proposed；僅規劃，尚未實作**
- **來源：** [Backlog.md — Task-3](../Backlog.md)（原 Review 範圍 L122–L128）
- **對應：** [FR-6 Report Retention Plan](resume-explorer-Feature-Request-6-report-size-plan.md) §5.2 / Phase 2A；[Task-1 Tests Plan](resume-explorer-Task-1-automated-tests-plan.md)
- **本次範圍：** 全命令互斥的需求／設計／測試規劃；**不修改 Production Code、Tests、Version，不實作 Cleanup，也不建立 Commit**。

## 1. Executive Summary／需求結論

**Approve with refinements：需求合理，推薦使用 OS-level File Lock（`FileStream` + `FileShare.None`）。** 方案在可靠性、跨 Shell、維護成本與向後相容性之間取得良好平衡；不需另建 Lock Manager、Service、背景 Worker 或 Queue。

**目標行為：** 在同一 Windows 使用者、**兩個命令實際解析並開啟相同本機鎖檔**、而且都經新版 `resume-explorer.ps1` 進入的前提下，任一時刻只允許一個 `Capture`／`Preview`／`Restore`／`PreviewRetry`／`Retry`（未來含 `Cleanup`）執行。第二個命令 **Fail Fast：不等待、不排隊、不背景重試**，並在任何 Action 層的 Explorer／Snapshot／Report 副作用前拒絕。

此項為**並行安全保護**，不是已證實的 Explorer Hang／Process Leak／Restore 失敗根因修復。它無法強制舊版 CLI、外部工具、直接呼叫 Core Functions、不同使用者或不同機器遵守同一把鎖。

### 1.1 需求合理性 Review

| 需求 | 判定 | 最終建議 |
| --- | --- | --- |
| 所有 Actions 都互斥，包括 Preview | 合理 | 保留：避免未來 Cleanup／Retry 與讀寫交錯 |
| 跨 PS 5.1／PS 7／CMD／Windows Terminal／VS Code／不同 PWD | 合理 | 同一檔案路徑 + OS File Sharing 保證 |
| Fail Fast，不排隊、不重試 | 合理 | 不新增 Lock Timeout／Wait Queue |
| 固定 `%LOCALAPPDATA%\ResumeExplorer\resume-explorer.instance.lock` | 合理 | 用 Windows Known Folder 取得絕對路徑 |
| 全命令持有 handle，最後 finally Dispose | 必要 | 含 final checkpoint、summary、family lock 釋放與未來同步 Cleanup |
| 不刪除鎖檔、不靠檔案存在判斷 Busy | 必要 | handle 才是真正的鎖 |
| 保留既有 Retry family lock | 必要 | 兩種 Lock 職責不同，不應移除或共用鎖檔 |
| Busy 時完全無副作用 | 需精確定義 | **Action 層**零副作用；允許 Lock 目錄自身的必要初始化 |
| CLI 相容性／版本 | 需驗收 | 並行第二個命令被拒屬有意的 observable change；保留其餘契約 |

## 2. Evidence First：目前程式／Git 狀態（2026-11-02）

1. `resume-explorer.ps1` 在 dot-source `resume-explorer.core.ps1`、建立 Config、`Assert-RestoreConfig` 後直接 `switch ($Action)`；目前**沒有全域 instance lock**。Core 檔 dot-source 只定義函式，不執行 Explorer 操作。
2. `resume-explorer.core.ps1` 的 `Start-RetryRun()` 已對 `<RootReportPath>.retry.lock` 使用 `[IO.File]::Open(..., OpenOrCreate, ReadWrite, FileShare.None)`，並在 `finally` 釋放。這僅保護該 Run Family 的 Retry，**不能阻擋其他 CLI Actions**。
3. `Complete-Run()` 負責 final checkpoint 與 summary；`Start-RetryRun()` 的外層 `finally` 才會釋放 family lock。全域鎖必須持續到兩者完成，以及未來同步 Cleanup 完成／跳過。
4. `Save-Snapshot()` 會寫 Snapshot；`Show-RetryPreview()` 會寫 `.retry-preview.json`；`Start-RestoreRun()`／`Start-RetryRun()` 會建立 Report。故 Guard 必須在 **Action Dispatch 前**。
5. Git commit `75f1319` 題名包含 `feat(lock)`，但其 Diff **只修改 Backlog.md 與 FR-6 計畫，沒有修改任何 Lock Production Code**。Task-3 仍為 Pending，不得誤判已交付。
6. 本輪開始時，branch 為 `codex/fr6-retention-plan`、工作樹乾淨；本次僅寫規劃，不改動程式或測試。

### 2.1 已觀察 Test Baseline（非 Task-3 驗收）

| Test | 本次觀察 | 注意 |
| --- | --- | --- |
| `tests/Issue2.Tests.ps1` | **39/39 Passed** | fake adapter；無真實 Explorer 動作 |
| `tests/RestoreSummary.Tests.ps1` | PS5.1 S01–S15 Passed、S16 Assertion Failed；PS7 **17/17 Passed** | **Task-4 已確認根因**：S16 對 `ConvertTo-Json` 空白格式作不穩定字串斷言；測試修正**尚未實作** |
| 真實 Explorer E2E／Task-3 跨 Process | **NotRun** | 此功能尚未實作 |

在 Task-3 開發前應先完成 [Task-4 S16 專項修復計畫](resume-explorer-Task-4-restore-summary-s16-regression-plan.md)：**RCA 已確認是 PS5.1 的 JSON 排版空白與 S16 字串比對不一致**，原 Exception、Warning 與可解析 JSON 已由受控診斷驗證；**修復尚未實作**。僅應在有證據的 S16 assertion 改為 JSON 語意解析，保留原安全契約，並驗證 PS5.1／PS7 完整通過。不可為了讓測試綠燈任意刪改 Assertions 或修改 Production JSON。

## 3. Alternatives／取捨

| 方案 | 跨 Process | 缺點 | 結論 |
| --- | --- | --- | --- |
| PowerShell 變數／process-local flag | 否 | 無法跨不同 Shell | 不採用 |
| PID／檔案存在即 Busy | 不可靠 | stale 檔、PID 重用、競態 | 不採用 |
| Windows Named Mutex | 是 | Namespace／Session／ACL／AbandonedMutex 額外複雜性 | 備選 |
| **固定 Path + `FileShare.None`** | **是（同實際檔案時）** | 須分類 sharing／ACL／disk errors | **推薦** |
| 中央 Service／Lock Manager／Queue | 是 | 維護成本超出本工具需求 | 不採用 |

## 4. Minimal Implementation Design

### 4.1 Lock Path 與 Scope

建議固定 Anchor：

```text
%LOCALAPPDATA%\ResumeExplorer\resume-explorer.instance.lock
```

- 從 `[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)` 取得基底；須檢查非空、為絕對路徑、可存取。若無法確認，**Fail Closed**。
- Lock Anchor 固定在 `ResumeExplorer` 底下、`Runs` **之外**；FR-6 不能刪除或輪替它。
- 不依賴 `$PWD`、`$PSScriptRoot`、`-Snapshot`、`-ReportPath` 或啟動 PowerShell 的終端機。
- 父目錄可受控建立；即使無法取得鎖，也允許 Lock 本身的初始化副作用。**Fail Fast／零副作用**指不執行任何 **Action 層** Explorer、Snapshot、Report／Retry 副作用。
- 不提供正式公開的 `-LockPath` 參數，避免使用者無意繞過全域互斥；測試可對內部 Helper 注入專用路徑。

### 4.2 Lock Acquisition／錯誤分類

使用既有技術模式：

```powershell
$stream = [IO.File]::Open(
    $lockPath,
    [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
)
```

- **保持 FileStream handle 開啟就是持鎖**。鎖檔存在不等於 Busy；不得以 `Test-Path`、PID 或定期刪檔來解鎖。
- 只有明確的 Windows **sharing violation**（例如 `ERROR_SHARING_VIOLATION`／Win32 32）回報 Busy。不要把所有 `IOException` 一律視為 Busy；`UnauthorizedAccessException`、磁碟與路徑錯誤應分別說明並 Fail Closed。是否支援其他等價分享衝突代碼，依實測證據決定。
- **錯誤分類只包住 Acquire 的 Open 操作**，不可將 Restore／Retry 中途的 `IOException` 誤報為 Lock Busy。
- Busy 或路徑失敗必須產生明確診斷和**非零 Process Exit Code**，禁止掉回正常 Action；不輪詢、不排隊、不背景 Retry。
- 正常結束時 `Dispose()` 而**不刪除 Lock Anchor**。被強制終止時 OS 會關閉 Process handle；這不保證 Report 已 checkpoint 或 Cleanup 已恢復。

### 4.3 最外層 CLI 生命周期與 SRP

建議最小變更為：在 `resume-explorer.core.ps1` 新增 `Get-ResumeExplorerInstanceLockPath`／`Enter-ResumeExplorerInstanceLock`（接受**內部 Path 注入**），在薄入口 `resume-explorer.ps1` 使用最外層 `try/finally` 包住所有 Action Dispatch。不要為此重構 `Complete-Run()`、`Invoke-TabTransaction()` 或 Snapshot／Report Schema。

**示意，非可直接取代現有 CLI 的完整實作：**

```powershell
. (Join-Path $PSScriptRoot 'resume-explorer.core.ps1')
Assert-RestoreConfig $config

$instanceLock = $null
try {
    $instanceLock = Enter-ResumeExplorerInstanceLock -Path (Get-ResumeExplorerInstanceLockPath)

    switch ($Action) {
        'Capture'      { ... }
        'Preview'      { ... }
        'Restore'      { ... }
        'PreviewRetry' { ... }
        'Retry'        { ... }
    }
    # Future FR-6: optional synchronous cleanup inside the same lock.
}
finally {
    if ($null -ne $instanceLock) { $instanceLock.Dispose() }
}
```

**必須保留的 Lock Order：**

```text
Acquire global instance lock
  -> Action (including all polls, final checkpoint and summary)
  -> Retry: release existing family retry lock in its own finally
  -> Future FR-6: optionally verify and synchronously cleanup OLD eligible families
  -> CLI finally: Dispose global instance lock
```

- Lock 不能在 `Complete-Run()` 返回或寫出 summary 就提前釋放；Cleanup 不應放入 `Complete-Run()` 的 `finally`。
- 目前尚無 Cleanup，故 Task-3 僅需覆蓋現有 Action 與其所有 finally。
- 不可為解決長時間持鎖而刪除 Anchor 或 Kill Explorer；真正的 COM/UIA Hang 屬 [Issue-4](resume-explorer-Issue-4-synchronous-timeout-plan.md)。

### 4.4 Backward Compatibility／Exit Behavior

- **有意的唯一主要行為變更：** 以前可以同時執行的第二個 `Preview`／`Capture` 等命令將被拒絕。
- 保留原有 CLI Action、參數、正常輸出、Snapshot v1、Report JSON、Retry family lock、identity verification、一次 Invoke／Navigate、checkpoint 及保守停止。
- Lock Busy、權限或 I/O 失敗應回傳非零；正常 Action 的原例外與 Exit Behavior 盡量維持。切勿在 `finally` 中以 `return`／`exit` 覆蓋原本失敗。
- 不加入 SendKeys、Clipboard、Registry、Explorer Restart／Kill 或新的外部安裝要求。
- 實作時同步更新 README／Backlog／FR-6 文件、版本與測試；**本次規劃不提前調整版本**。
## 5. Tests：安全隔離與可驗證性

### 5.1 兩層測試策略

1. **Helper Unit／Cross-Process Tests（主軸）**：為 `Enter-ResumeExplorerInstanceLock -Path <testPath>` 提供內部注入，使用每次唯一的 `%TEMP%\ResumeExplorer-LockTests-<GUID>`、兩個真正獨立的 `powershell.exe`／`pwsh.exe` PIDs 與可控制的 ready/release 訊號。完全不接觸真實 Explorer、正式 Lock Anchor 或現有 Report。
2. **CLI Orchestration Test（必需）**：另行驗證 CLI 在任何 Action Dispatch 之前必定 Acquire，且 Busy 時 Explorer／Snapshot／Report 副作用計數全為 0。可使用隔離的測試入口／暫存副本與安全 Fixture（不得修改正在使用的 Production CLI），或使用專用測試 Windows Account／Profile；不為了測試在正式 CLI 暴露繞過 Lock 的公開參數。**只有 Helper Test 通過，還不能宣稱 CLI Guard 已覆蓋所有 Action**。
3. **真實 Explorer E2E（非預設）**：需獨立、互動式 Windows Session 與明確 opt-in；不對使用者現有 Explorer 視窗或 Process 執行測試與清理。

跨 Process 同步應由明確 ready/release mechanism 決定性協調，**不可只靠任意 Sleep 猜測已持鎖**。子 Process 具最長等待、完整清理與獨立 PID 驗證；若失敗僅處理**本次測試產生的子 Process**，絕不終止 `explorer.exe`。

### 5.2 必要測試矩陣

| ID | Scenario | 預期斷言 |
| --- | --- | --- |
| L01 | 首次取得 Lock | 成功取得 FileStream、固定 Anchor |
| L02 | Process A 持鎖，Process B 嘗試 | B Busy、Fail Fast、非零 Exit；A 未被干擾 |
| L03 | A 正常 Dispose，B 再取得 | B 可成功取得 |
| L04 | Anchor 存在但 handle 已釋放 | 不誤判 Busy |
| L05 | 不同 `$PWD`／Terminal／Script 位置 | 同一 Lock Path 時仍互斥 |
| L06 | PS 5.1 ↔ PS 7 | 兩者皆可用時跨版本互斥；不存在的版本標記 NotRun |
| L07 | Capture vs Restore | 第二個 CLI 無 Action 副作用 |
| L08 | Preview vs Retry／PreviewRetry | 所有 Action 同一互斥規則 |
| L09 | Lock Path 無權限 | Fail Closed、不是 Busy |
| L10 | 磁碟、路徑或其他 I/O Error | 不誤報 sharing conflict |
| L11 | Action Throw | 原例外保留、鎖在 finally 釋放 |
| L12 | 持鎖測試 Process 被終止 | 下一個可重新取得，Anchor 不必刪除 |
| L13 | CLI Busy | Explorer 呼叫 0 次；Snapshot／Report／sidecar 寫入 0 次 |
| L14 | Retry family lock／global lock | 原 family lock 先釋放，global 在 CLI finally 釋放 |
| L15 | 未來 FR-6 Cleanup 過程 | 第二個 CLI 仍 Busy、不能插入 |
| L16 | 多輪並行測試 | 沒有同時讓兩個 Process 進入受保護 Action |
| L17 | Busy 時現有 Snapshot／Report | 內容、Hash 與時間戳不變（Lock 初始化除外） |
| L18 | Ctrl+C／正常離開 | 可控環境實測釋放；若不可控標記限制 |

跨 RDP Sessions 只有在**同一 Windows 使用者、同一實際本機 Lock Path，且共享 Windows File Sharing 語義**得到確認後才列入驗收。跨不同 Windows 帳號／機器沒有保證。

### 5.3 原測試回歸完整性

- **Task-4 已完成 S16 RCA，尚未實作修正**：PS5.1 的 `ConvertTo-Json` 冒號後為兩個空格，S16 錯誤要求單一空格；詳見 [Task-4 Plan](resume-explorer-Task-4-restore-summary-s16-regression-plan.md)。**既有測試不是為了讓新版程式通過而可以任意改寫的目標**；Task-4 僅在已驗證的錯誤斷言做最小、語意更強的修正，且保留原例外／Warning 等契約。
- 建議新增 `tests/InstanceLock.Tests.ps1` 及必要的 test worker／fixture；沿用現有 deterministic testing style，不為本功能強制引入 Pester 5 或重寫整個架構。
- 實作後重跑 `tests/Issue2.Tests.ps1`、`tests/RestoreSummary.Tests.ps1`、新的 Lock Tests，記錄 Exit Codes、通過／失敗／NotRun 與使用的 PowerShell 版本。
- 沒有執行真實 Explorer E2E，不得宣稱 E2E Passed。

## 6. Implementation Phases／Priority／Dependency Gate

| Phase | 內容 | Exit Gate |
| --- | --- | --- |
| **0. Baseline** | 核對 Git 狀態、既有測試；依 Task-4 修正已確認的 S16 格式敏感斷言並完成跨版本回歸 | Task-4 驗收：PS5.1／PS7 RestoreSummary 17/17 Passed、原安全檢查不弱化 |
| **1. Lock Helper** | Known Folder、檔案排他 Open、Busy／I/O 分類、內部 Path Injection | L01–L06、L09–L12 的 deterministic／cross-process tests |
| **2. CLI Guard** | 在薄 CLI 的最外層 `try/finally` 包 Action Dispatch；不更動 Restore/Retry core safety | L07–L08、L13–L14、L17 和原回歸測試 |
| **3. Docs / Version / Validation** | 更新 README／Backlog／FR-6 references／版本，留存測試證據 | 全部可交付 Gate 與聚焦 Git Diff |
| **4. FR-6 Integration（後續獨立工作）** | FR-6 Phase 3 Safe Cleanup → Phase 4 Synchronous Post-run Cleanup | 需 Task-3 驗收、FR-6 Phase 0–2 及跨檔刪除安全 Gate 全通過 |

**相對優先序**：

```text
Track A: Task-3 global CLI guard -----------------------+
                                                        +--> FR-6 Phase 3: Safe Cleanup --> Phase 4: Post-run Sync
Track B: FR-6 Phase 0 --> Phase 1 --> Phase 2 ---------+
            + independent crash-recovery/deletion safety gate
```

- Task-3 **不依賴** FR-6 Phase 0–2，可以先獨立實作，且不改動 FR-6 Report Schema。
- Task-3 是 FR-6 **實際清理** Phase 3/4 的必要前置，**不是** FR-6 唯讀分析／DryRun 的前置。
- Issue-4 的同步 COM/UIA Hang 及 Issue-6 的 Google DriveFS 歷史 Hang **不是 Task-3 的前置或已確認根因**。
- 即使 Task-3 已實作，FR-6 的多檔 Family Delete 仍**不具原子性**；未確認完整 Family、Pinned、A／Unknown、外部讀寫者、Crash Recovery 時應 Fail Closed／Skip，不能直接據此上線 Cleanup。

## 7. Acceptance Criteria / Definition of Done

- [ ] 全部現有 CLI Actions 在任何 Action 層 Explorer／Snapshot／Report 副作用前取得全域鎖。
- [ ] 共用相同 Lock Path 的不同 PowerShell Process 不能同時進入 Action；Busy Fail Fast、非零 Exit、不等待。
- [ ] Lock Path 使用 LocalApplicationData Known Folder，與 PWD／Script 路徑／ReportPath 無關且不位於 `Runs`。
- [ ] 不使用 Lock Anchor 存在與否判斷 Busy；不存在 handle 即可重新取得，不刪除 Anchor。
- [ ] Busy／Access Denied／一般 I/O 錯誤分類正確；例外／退出後能再次取得鎖。
- [ ] 既有 per-family Retry Lock／原子 checkpoint／identity 與一次 Invoke／Navigate 保護不被破壞。
- [ ] Helper、跨 Process、CLI orchestration 及相關回歸測試有實際且可重現的結果。
- [ ] S16 已調查並處置／明確註記為既有 blocker，沒有任意削弱既有測試。
- [ ] 正常 Action 的 CLI Parameters、Snapshot/Report Schema、console output 與 Exit Behavior 保持相容。
- [ ] README／Backlog／FR-6 Plan／版本及測試紀錄同步；正確說明有意改變的同時執行行為。
- [ ] 沒有操作真實 Explorer、重啟 Shell、改 Registry／Execution Policy 或引入不必要的依賴。
- [ ] FR-6 未來 Cleanup 在 global lock 內且 Retry family lock 已釋放後執行，Cleanup 自有安全 Gate 另驗收。

## 8. Risks／限界

1. **已存在的 S16 測試異常**：Task-4 已驗證是跨 PowerShell 版本的 JSON 排版格式敏感斷言，**尚未修正**；不得無證據歸因 Task-3 或把測試修正視為已完成。
2. **只有合作的新 CLI 受限**：舊版、直接 Core Caller、第三方、不同帳號或機器不受約束；跨帳號共用 ReportPath 的 Cleanup 應禁止／保守處理。
3. **Explorer Hang 不會因 Lock 消失**：COM/UIA 若卡住，CLI 長時間持鎖並拒絕其他 Action；不得刪 Lock 或強制殺 Explorer 作為修復。
4. **跨 PS 版本／RDP Session**：須實際驗證，未測就記錄 NotRun；無法僅憑設計宣稱相容。
5. **全域互斥不等於多檔刪除 Crash Recovery**：FR-6 必須獨立驗證與防護。

## 9. 預期交付與參考

**實作階段候選檔案：** `resume-explorer.ps1`、`resume-explorer.core.ps1`、新增 Lock Tests／test worker、`README.md`、`Backlog.md`、FR-6 Plan、版本／驗證紀錄。**本次只寫入 Markdown 規劃，不修改程式碼、既有測試、版本或產生 Commit。**

- [Backlog.md](../Backlog.md)：Task-3 描述、優先序、與 FR-6 Phase 3/4 的相依。
- [FR-6 Report Retention Plan](resume-explorer-Feature-Request-6-report-size-plan.md)：同步 Cleanup 的完整 Family／Crash Recovery 保護。
- [Task-1 Automated Tests Plan](resume-explorer-Task-1-automated-tests-plan.md)：既有測試基礎與隔離測試方法；文件內部分歷史敘述未完全反映目前已拆分的 Core 和 39 個 adapter tests，未來可另行刷新。
- [Issue-4 Synchronous Timeout Plan](resume-explorer-Issue-4-synchronous-timeout-plan.md)：獨立調查同步 COM/UIA 卡住問題。
