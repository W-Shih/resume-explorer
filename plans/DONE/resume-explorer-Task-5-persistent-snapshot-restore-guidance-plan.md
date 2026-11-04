# Task-5 — 持久保存測試前配置與結束後還原提示：詳細實作計畫

- 日期：2026-11-03。
- 狀態：**Done — 核心實作與主要流程驗收完成（2026-11-04）**。A01 與測試編碼 regression 已修正；本機離線 141 項通過，使用者 VM smoke Passed／Exit 0、手動 Restore 4/4 Verified。結案依據與未完成的延伸驗證見 §17 及 Backlog；不宣稱整份矩陣全數通過。
- Review 基準：`9dd7f9b`；開始時工作樹乾淨。
- 使用者決策：採方案 2；Snapshot 保存於 `%LOCALAPPDATA%\ResumeExplorer\Snapshots\BeforeSmoke\<RunId>.json`；只要已成功保存，後續成功、失敗、取消或程序 crash 都應提供還原入口。
- 原始規劃範圍（歷史）：當時只新增計畫，不修改 runner／產品／測試，不執行 Capture／Restore／E2E。後續實作與驗收依時間記錄於 §11–17。
- 關聯：[一鍵 SOP](../../tests/Integration/ONE-CLICK.md)、[關窗 regression 計畫](resume-explorer-Task-5-multi-group-close-regression-plan.md)、[既有 VM 驗收](../../tests/Integration/TASK5-VM-ACCEPTANCE.md)。

## 1. 需求解讀與設計決策

使用者在選擇 `S (儲存後關閉)` 後，保存的是測試前可能仍在使用的 Explorer groups。這份資料不能只當暫時測試證據；它應可在測試完成或中斷後，透過正常 Restore 明確找回。

本次採用：

1. **持久保存、每次唯一命名**：使用指定的 BeforeSmoke 目錄，沿用正式 V1 Snapshot 格式與正式 Capture；不覆寫日常預設 Snapshot。
2. **明確且可直接複製的還原命令**：在原有 JSON 輸出之後再顯示測試結果、Snapshot、命令及命令檔位置；不用切換目錄或替換 placeholder。
3. **關窗前持久化復原資料**：先提交 Snapshot、驗證依據與文字命令檔，才允許關閉原視窗。不能依賴測試結束時記憶體中還有 `$suite.ExistingSnapshot`。
4. **前景監督程序處理測試程序 crash**：公開入口由前景 supervisor 啟動互動 worker；worker 異常退出後，仍由存活的 supervisor 顯示該次 RunId 的復原資訊。
5. **不自動 Restore**：本方案只提供命令，不新增測試後開窗／自動還原／重試。Restore 由使用者決定執行時間。

必要界線：若 supervisor、整個終端、VM 或作業系統也被關閉，沒有存活程序能保證「當場在該終端印出訊息」。此時以**關窗前已存在的持久命令檔及 Snapshot**作復原入口，不宣稱已顯示結束提示。這不是以 finally 包住就能消除的限制。

## 2. 現況與問題定位

| 目前位置 | 事實／缺口 |
| --- | --- |
| [產品 CLI](../../resume-explorer.ps1) `Snapshot` 預設 | `%TEMP%\ExplorerTabs-snapshot.json`；不應被本功能改寫 |
| [Lifecycle](../../tests/Integration/ExplorerSmoke.Lifecycle.ps1) `Save-SmokeExistingSnapshot` | 目前將正式 Capture 寫入 TEMP suite root 的 `existing-snapshot.json`；核對 groups、原分頁與 SHA 後回傳路徑 |
| [OneClick core](../../tests/Integration/ExplorerSmoke.OneClick.Core.ps1) | `$suite.ExistingSnapshot` 要等保存函式回傳後才設定；finally 仍可能因 suite-result 寫入錯誤拋出 |
| [公開入口](../../tests/Integration/Start-ExplorerSmoke.ps1) | 直接在同一程序呼叫 coordinator、輸出 JSON、exit；沒有 JSON 後的還原摘要，也沒有獨立存活的 crash 提示者 |
| [.cmd](../../tests/Integration/Run-ExplorerSmoke.cmd) | 只顯示 exit code／pause，無法識別本次持久 Snapshot；單靠修改 .cmd 也不能覆蓋直接執行 PowerShell 入口的使用者 |
| [SOP](../../tests/Integration/ONE-CLICK.md) | 雖有 Restore 示例，但使用者仍須自行替換 suite 路徑；CLI 結束時沒有可直接複製的完整命令 |

既有缺口不只「最後多印一行」：如果函式已寫出完整檔案、但在回傳路徑或更新 suite-result 前失敗，現行 result 仍可能是 null；如果 pwsh 直接終止，finally 也不能保證可用。

[.NET Environment.Exit 文件](https://learn.microsoft.com/en-us/dotnet/api/system.environment.exit) 明確說明從 try／catch 呼叫 Exit 時不執行 finally。[PowerShell try/catch/finally 文件](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally) 亦指出 Ctrl+C 停止 pipeline 後，即使 finally 執行，送往 pipeline 的輸出也可能不顯示。因此單程序 catch/finally 只能作一般例外的保障，不能完整滿足本 spec 的 crash 情境。

## 3. 範圍與相容性契約

- 保留 `Run-ExplorerSmoke.cmd`、`Start-ExplorerSmoke.ps1 -Run` 與 `-RequireVisualReview` 使用方式；不增加必填的人工輸入。
- 無 `-Run` 與 dot-source import 仍不啟動 worker、不列舉 Explorer、不建立目錄／檔案、不做復原歷史搜尋。
- 拒絕授權、沒有既有視窗、選 `C`、選 Enter 取消，均不建立新的持久 Snapshot 或假的還原提示。
- 只有 `S` 成功保存的該次配置提供還原入口；不能抓取「最近一次」其他 run 的 Snapshot 代替。
- 保留 SC_CLOSE 整窗命令、逐窗一次投遞、共用 deadline、可靠觀測／identity／hash gates、失敗保留現場、不 replay 的契約。
- 不修改產品 Actions／參數、日常 Snapshot 預設、Snapshot V1／Report V1、Restore／Retry 行為或既有產品測試斷言。
- 新增的是 harness recovery metadata，不是新產品 Snapshot schema。
- 不自動開啟或執行還原命令檔，不產生會被執行的 `.ps1`／`.cmd` 捷徑。
- 不新增 retention／自動刪除政策；BeforeSmoke 不屬於正式 Runs 或 FR-6 run-family 清理範圍。

## 4. 持久儲存與成功保存的定義

### 4.1 目錄、命名與所有權

使用 Windows Known Folder `LocalApplicationData` 解析 `%LOCALAPPDATA%` 的實際位置，建立固定子路徑：

```text
%LOCALAPPDATA%\ResumeExplorer\Snapshots\BeforeSmoke\
  <RunId>.json                 # 正式 V1 Snapshot，發布後不再修改
  <RunId>.recovery.json        # 已驗證內容的 descriptor，供 supervisor 找回
  <RunId>.restore.txt          # 人可閱讀的完整還原命令與說明
  .<RunId>.<nonce>.pending     # 本次提交前暫存；不是可還原完成檔
```

- RunId 使用本次 suite 的 32 位 GUID；supervisor 在記憶體中先配置，再傳給 worker，SuiteRoot 也使用同一 ID，以便兩者確實對應。
- 不以機器上固定的 latest.json／全域環境變數／另一個 terminal 的紀錄交換路徑。
- 解析結果須是絕對路徑；Known Folder 空值或不可寫時明確失敗，不偷偷改回 TEMP 或日常預設 Snapshot。
- 驗證根目錄與新檔仍位於已解析的 BeforeSmoke 範圍，處理 reparse／path traversal，不對任意外部檔案 overwrite／delete。不得自行修改使用者的 ACL、系統設定或清理其他 run。
- 每個 run 檔案採 create-new／不覆寫語意；碰撞停止，不使用已存在的同名檔案當本次備份。
- SuiteRoot 的 `ExistingSnapshot` 改為指向此持久 JSON。TEMP 仍保存測試 cases、Capture stdout/stderr 及一般驗證證據，不另維護第二份可能不同步的主要 Snapshot。

### 4.2 復原 descriptor 最小內容

`<RunId>.recovery.json` 預計包含獨立 harness version、RunId、SuiteRoot、固定最終 Snapshot 路徑、SHA-256、CapturedAt／ValidatedAtUtc、原視窗／分頁數、工具與 pwsh 完整路徑、必要的 machine/user 關聯，以及 `Validated: true`。

descriptor 的 `Validated` 指內容已核對，**不能單獨代表 final Snapshot 已提交**。supervisor 必須同時確認本次固定最終檔存在、V1 可讀且 hash 一致，才標示 Saved。不得把檔案存在或 CLI Exit 0 單獨視為成功保存，也不能把其中任意字串當 shell 指令執行。

### 4.3 提交流程與 crash window

1. 使用者選 S，起始 observation 必須可靠。已取得本次 suite lock，保留既有隔離聲明與 runtime 檢查。
2. 正式 CLI Capture 寫入本次專用 staging 檔；staging 不得是日常預設檔或其他 run 的檔案。
3. 要求 CLI Exit 0，解析 V1、核對完整 window/path multiset，重新 Observe 並確認原有分頁 identity／path／fingerprint 未改變；計算將發布之確切 bytes 的 SHA-256。
4. 產生完整 Preview／Restore 命令；以同目錄暫存＋原子發布且不覆寫方式，先提交 recovery descriptor 與 restore.txt。兩者任何一份失敗，停止且不關窗。
5. 將已驗證 staging 在同一 filesystem 原子發布為 `<RunId>.json`，不覆寫既有 final。**此 final 檔存在且與已提交 descriptor 的 hash 相符，是成功保存的 commit point。**
6. 設定 `$suite.ExistingSnapshot`，保存 suite checkpoint；立即顯示持久 Snapshot／命令檔位置及還原命令，然後才開始關閉原視窗。
7. 後續不改寫或刪除這三個已提交檔案。即使 suite-result 更新失敗，也不移除已成功提交的備份。

這個順序刻意讓復原資料先於 final Snapshot 可用：若在 final 發布前 crash，原視窗尚未關閉，不能宣稱備份已成功；若在 final 發布後、函式回傳或記憶體欄位設定前 crash，parent 仍能以自己的 RunId 找到 descriptor、hash 一致的 final 與完整命令檔。

若只有 staging／descriptor／restore.txt 而沒有有效 final，視為未完成，不產生「已保存，可直接還原」的正常提示。失敗只清理明確認領的本次 staging；不得誤刪已發布 final 或其他 run。可能留下的未完成 sidecars 要有清楚診斷，不新增背景清理程序。

此設計針對程序失敗與正常 filesystem 語意，不宣稱斷電、磁碟故障或儲存裝置損毀時必然保有資料。

## 5. 前景 supervisor 與 worker

### 5.1 為何需要程序邊界

只在現有 `Invoke-SmokeOneClick` 加 finally，無法在該 pwsh 自身被終止後印訊息。只由 .cmd 查找 Snapshot，又會漏掉直接使用 PowerShell 入口的路徑。因此以現有公開 PowerShell 入口作前景 supervisor，讓 .cmd 與直接執行共享同一套行為。

```text
Run-ExplorerSmoke.cmd 或直接執行 Start-ExplorerSmoke.ps1 -Run
  → supervisor：配置 RunId，前景啟動 worker，持有 process handle
      → worker：原有互動授權／baseline／保存／關窗／E01／E02／JSON
  → 確認 worker 已結束
  → supervisor：讀本次持久復原資料，於 JSON 之後印測試摘要與完整命令
  → 保留既有結束碼，.cmd 顯示 exit code 並 pause
```

### 5.2 實作邊界

- `Start-ExplorerSmoke.ps1` 保留公開參數與安全預設，授權流程仍由 worker 執行；supervisor 不增加第二次同意提示。
- 新增內部 worker entry，例如 `Invoke-ExplorerSmoke.OneClickWorker.ps1`；只負責執行原 coordinator、輸出原 JSON 與結束碼。內部接收 canonical RunId，不接收任意外部 worker／命令路徑。
- 使用目前的 PS7 engine、`-NoProfile -Sta -File` 及分離的 argument list。worker 繼承當前互動 console，不另開視窗；先用不操作 Explorer 的 Read-Host fixture 驗證輸入／輸出與 Ctrl+C 行為。
- supervisor 持有本次 child 的 process handle／PID，只有確認 child 已退出，才印「測試已結束」。不能因 wait 中斷就假設 child 已停止，或讓使用者在 worker 仍執行時誤以為可安全還原。
- 若 Ctrl+C 導致 child 存活狀態不明，明確標示「程序可能仍執行，請先確認再使用還原命令」；不殺 Explorer、不自動重新開始測試。
- 不建立背景 service、daemon、排程、登入鉤子、全域監視器或無限輪詢；這個額外程序只存在於本次前景執行期間。
- 原有 coordinator／case locks 留在 worker，supervisor 不接管或刪除其鎖檔。worker crash 後由 OS 回收 handle；保留原始證據。
- library 函式仍可離線直接測試，但「worker 自身 crash 後有另一程序印提示」的契約限公開的一鍵 entry，不冒稱直接呼叫內部函式也有監督者。

### 5.3 結果與 exit codes

正常 0 Passed、1 Failed、2 NotRun／pending、3 Blocked 保留。worker 正常回傳時，supervisor 保留其結果，不為印命令而改寫原 suite-result／Error。

非預期 child exit／缺少合法結束結果視為程序異常，公開入口以失敗結束並顯示原始 child exit code；不可只因 child raw exit 0 就宣稱 Passed，還需該次 suite 的成功結果。原 JSON 或 TEMP suite-result 若無法取得，只能顯示「測試異常結束／結果不明」，持久 Snapshot 的復原提示仍可獨立完成。

通知錯誤與測試錯誤分開呈現。若 child 原本非零，提示／檔案讀取例外不能掩蓋它。若測試 Passed 而完整摘要發生錯誤，保留測試結果並明確顯示復原提示警告／既存命令檔位置，不宣稱提示已成功送達，也不偷偷重跑測試或 Restore。

## 6. 還原指令與輸出契約

### 6.1 完整命令

產生以下形式的 **PowerShell 7 命令**，所有位置均為實際完整路徑：

```powershell
& '<實際 pwsh.exe 完整路徑>' -NoProfile -Sta -File '<實際 resume-explorer.ps1 完整路徑>' -Action Restore -Snapshot '<本次持久 Snapshot 完整路徑>'
```

上面只是計畫示意；實際輸出不得包含 `<...>`、相對路徑、`$env:TEMP` 或要求使用者自行拼接的片段。明示「請在 PowerShell 7 貼上執行」，避免誤當 cmd.exe 語法。

- 依啟動工具的真實位置定位產品 entry，使用當前已選定 PS7 engine 的完整路徑；不依賴執行時 PWD 或猜測使用者工具目錄。
- PowerShell single-quoted literal 中的單引號需倍寫；空白、中文、`$()`、`&`、括號及反引號都不得在產生命令時被展開或執行。
- 不用 Invoke-Expression，不把 recovery JSON 的自由文字當作命令執行。命令由可信入口路徑與本次已驗證 Snapshot 路徑產生。
- `restore.txt` 保存相同完整 Restore 命令，可另提供 Preview 命令；不自動執行任何一條。
- 若工具稍後被搬移／刪除，歷史命令的工具路徑可能失效；Snapshot 仍是正常 V1，可改用目前工具加 `-Snapshot`。SOP 說明此限制。

### 6.2 正常結束顯示

在 worker 原有 JSON **之後**、.cmd 的最終 exit-code 訊息／pause **之前**，由 supervisor 統一顯示一次：

```text
測試結果：Passed
測試前配置：<實際完整 Snapshot 路徑>
尚未自動還原原有 Explorer 配置。

如需還原，請在 PowerShell 7 複製執行：
<實際完整 Restore 命令>

還原指令已保存：<實際完整 restore.txt 路徑>
```

保存完成時也先顯示一次，讓 supervisor／終端稍後一併消失時，使用者仍曾看到持久入口。這是「保存當下＋最終摘要」兩個必要時點，不是每一層 catch/finally 都重複印相同內容。

### 6.3 失敗、取消與中斷顯示

- 只要本次 final Snapshot 與 descriptor 驗證成功，即使 worker Result／ExistingSnapshot null、suite-result 損毀、checkpoint 寫入失敗、E01／E02 失敗或目視取消，仍顯示同一個持久路徑及完整命令。
- 顯示實際 Failed／Cancelled／AwaitingVisualReview／異常結果；不能為提供還原入口將結果改為 Passed。
- 補充「目前可能仍有測試視窗或部分原視窗，請先檢查；Restore 會新增視窗，重複執行可能產生重複分組」。不斷言所有原視窗已被關閉，亦不自動清理殘留來方便還原。
- snapshot／descriptor／hash 缺失或變更時不能靜默改用其他 run，或謊稱沒有曾保存。顯示該次預期位置、命令檔及具體驗證失敗原因，將正常可還原狀態標為無法確認；不自動執行可能不完整的檔案。
- 不用全域 latest 檔或 stdout 中搜尋路徑作復原來源；以 supervisor 已知的 RunId 與 BeforeSmoke base 定位，避免顯示其他 run 的配置。

## 7. 故障模式與保證範圍

| 情境 | 要求的行為 |
| --- | --- |
| S 成功，整套 Passed | 最後 JSON 後顯示完整命令；Snapshot／descriptor／txt 留存 |
| S 成功，後續 Failed／Blocked／目視取消 | 顯示原結果及還原入口；警告可能有殘留，不自動 Restore |
| final 已發布，但保存函式回傳／suite checkpoint 失敗 | supervisor 依 RunId＋descriptor＋final hash 找回，不能依賴 result.ExistingSnapshot |
| Capture／validation／command-file 提交失敗 | 不關閉原窗；不能把 staging 當 Saved；顯示保存失敗原因 |
| worker 非 catchable 結束，supervisor 存活 | 確認 child 退出後顯示異常／raw exit code與已提交復原命令 |
| Ctrl+C／父層 wait 中斷 | best effort 摘要；確認 child 狀態，不能假稱整套已結束；持久命令檔可另行查看 |
| 終端／supervisor／VM 也消失 | 無法保證當場輸出；關窗前提交的檔案仍是復原入口，且保存時已提示位置 |
| 子程序掛住未退出 | 不宣稱已結束或可直接還原；不新增強制 timeout／殺程序；仍有事前持久命令檔 |
| C、沒有既有視窗、S 前取消／拒絕授權 | 不建立新 Snapshot，不提供其他 run 的 Restore 命令 |
| Snapshot 之後被外部清理、改寫或磁碟不可讀 | 明確說明無法驗證／恢復資料；不虛構成功、不從錯誤路徑 Restore |

硬終止整個應用程式時「結束後仍必定在原終端顯示」在技術上無法保證。本方案對此提供 durable recovery，而非聲稱 finally 永遠能跑；不需要為消除此限制而加裝永久背景監督服務。

## 8. 預計檔案與實作順序

| 步驟 | 工作與檔案 | 通過門檻 |
| --- | --- | --- |
| A | 先建無 Explorer 的 supervisor／worker fixture，驗證互動 console、參數、正常與異常 exit；不修改 GUI 邏輯 | 同一公開入口可覆蓋 .cmd／直接 PS 啟動，且不多開 console；若 host 有限制先記錄並解決 |
| B | 新增 `tests/Integration/ExplorerSmoke.Recovery.ps1`，集中 BeforeSmoke 路徑、descriptor／command 提交、讀取驗證、格式化命令／提示；import 零副作用 | Fake filesystem／path／IO fault tests 先建，不碰真實使用者資料 |
| C | 調整 `ExplorerSmoke.Lifecycle.ps1` 的保存流程與 `ExplorerSmoke.OneClick.Core.ps1` 的 RunId／recovery context | final commit 後任何失敗仍可找到正確 Snapshot；commit 前不關窗 |
| D | `Start-ExplorerSmoke.ps1` 作前景 supervisor；新增內部 worker entry，搬移目前 entry 執行部分，不重寫 coordinator | default／import／授權／GUI ordering 與 exit-code 契約保留 |
| E | 接上正常／異常的最終摘要；.cmd 維持呼叫公開入口與原 exit-code／pause，不用 shell 拼接 Snapshot 命令 | JSON 後有一次清楚提示；child crash 也能由 parent 提示 |
| F | 擴充 `ExplorerSmoke.OneClick.Tests.ps1`；視規模新增獨立 Recovery tests，加入真正 baseline helper | 原斷言保留，新增情境全通過，expected count 依實際數量更新 |
| G | 更新 ONE-CLICK.md、Integration README、產品 README 的測試段落、驗證紀錄、Backlog 與本計畫 | 說明持久目錄、命令找回、Crash 保證界線、無自動 Restore／無自動清理 |
| H | 一次針對儲存／提示的專用 VM 操作驗收 | 既有 cases／cleanup 通過、持久 Snapshot 與提示正確；不因純文字修訂反覆重跑 GUI |

如需增加 adapter／context，維持內部相依注入，測試根目錄必須指向測試自行建立的唯一目錄；不能讓離線 baseline 把合成 Snapshot 寫入真實 BeforeSmoke 或日常 Snapshot。現有 47 項 OneClick test 的保存路徑預期可因已批准需求更新，但完整性／先保存後關窗／失敗不關窗等斷言不得放寬。

## 9. 測試與驗收矩陣

### 9.1 deterministic 與 IO fault injection

| ID | 情境 | 必要斷言 |
| --- | --- | --- |
| R01 | Known Folder 正常、空值、不可寫、reparse／越界 | 正確 BeforeSmoke base；錯誤不 fallback 預設或 TEMP、不關窗 |
| R02 | 多 run／並行／同名碰撞 | 每次 ID 唯一；不覆寫舊 final／日常 Snapshot，不混用其他 run 的提示 |
| R03 | Capture 非零、JSON 不完整、groups 不符、原分頁改變 | 不發布可還原 final、不關窗；現有完整性斷言保留 |
| R04 | staging、descriptor、txt、final 發布各個 IO fail point | commit 前無關窗；已提交 final 不刪；保存失敗與成功界線明確 |
| R05 | crash／throw 在 metadata 前、metadata 後 final 前、final 後 result 設定前 | 前兩者不宣稱 Saved；最後一者不靠記憶體也能產生正確命令 |
| R06 | S 成功後 suite-result 寫入／JSON serialization／finally 失敗 | 原始錯誤不被吞掉；持久復原入口仍顯示 |
| R07 | Passed、Failed、Blocked、目視取消／正常 Enter 路徑 | 每個有成功備份的結束結果都有命令，無備份不亂印；不執行 Restore |
| R08 | 只有 partial receipt／final 缺失／hash 變更／另一 ID／另一 user metadata | 不當成功、不混用歷史 latest；有明確診斷／預期命令檔位置 |
| R09 | 工具與 Snapshot 路徑含空白、中文、單引號、`$()`、`&`、括號、反引號 | 命令 parser／fake transport 收到精確 literal args；不做任何額外執行 |
| R10 | 不同 PWD／工具移動後的歷史文字命令 | 正常摘要用當前工具絕對路徑；歷史指令失效限制明示，Snapshot 不改寫 |
| R11 | default／import／拒絕授權／C／沒有既有窗 | 無持久目錄／Snapshot／worker 副作用（default/import）；授權後其他情境不偽造備份 |
| R12 | final commit 與 close callback ordering | descriptor、txt、final、checkpoint 都成功後才可關窗；checkpoint 失敗保留已保存檔 |
| R13 | 長 JSON／提示內容與順序 | 原 JSON 完整輸出後再印完整摘要；無 placeholders、相對路徑、重複 finally 提示 |
| R14 | 原生 callback／lock／case failure | 不重送／replay、不自動清理現場；恢復提示不干擾原錯誤與釋放 |

### 9.2 真正程序邊界測試（不操作 Explorer）

建立專用 test worker fixtures 與唯一 synthetic recovery 目錄，不在正式 worker 加 crash/debug bypass 參數。

| ID | 情境 | 必要斷言 |
| --- | --- | --- |
| P01 | 直接 PS 入口與 .cmd 呼叫、不同 PWD | 都經同一 supervisor；參數 literal、互動正常、額外 console 不出現 |
| P02 | fixture 正常 exit 0／1／2／3 | 正常 mapping、JSON／摘要順序與已知結果一致 |
| P03 | fixture 提交有效 Snapshot 後 `[Environment]::Exit(17)`，略過 finally | parent 仍存活；輸出異常、raw exit=17、該次完整命令；GUI 呼叫數為零 |
| P04 | fixture commit 前 abnormal exit、或 raw exit 0 但沒有合法 suite 結束結果 | 不偽報保存／Passed；不用另一 run 當替身 |
| P05 | supervisor 讀取／格式化拋錯，child 原本失敗 | 不掩蓋 child 原始結果；best effort 指向已提交命令檔 |
| P06 | worker／supervisor 單元測試的取消／wait 中斷與 child 存活狀態 | 不印「已結束」假象；無 kill Explorer、無自動 Restore |

P03 以測試自己啟動的無 GUI process 模擬直接終止，不故意掛死 Shell、觸發 OS crash 或終止使用者程序。終端一併關閉、Ctrl+C 的實際 host 差異可作人工驗證，不將不可重現的 signal 行為偽稱 deterministic 保證。

### 9.3 專用 VM 的精簡驗收

1. 正常入口選 S，跑完既有 E01／E02；確認 persistent JSON／descriptor／txt 存在，日常預設 Snapshot bytes 未變，最後提示在 JSON 後且路徑與該次 RunId 相符。
2. 在測試桌面由操作者另行複製執行輸出的 Restore 命令，確認它指向保存的原配置與正常產品 summary；這是命令的人工驗收，不是 runner 新增自動 Restore。
3. `-RequireVisualReview` 下在保存後取消目視，確認仍有正確提示且現場保留；避免為此改寫測試報告。
4. 用無 Explorer 的專用 fixture 驗證 abnormal exit 的 parent 提示。若需要檢查終端被關閉，使用可拋棄 session，之後從 BeforeSmoke 目錄讀 restore.txt；不強求原終端再出現。

離線基準為實作前的 39／17／23／47＝126；本次規劃沒有重跑或宣稱新測試已通過。未來依實際新增數更新 baseline，不能減少 expected、跳過失敗或只靠多印 Passed 取得 green。原產品 39／17 tests 預期維持內容。

## 10. 完成標準與限制（結案證據見 §17）

- [x] final V1 Snapshot 使用指定持久目錄與唯一 RunId，不覆寫日常預設檔。
- [x] 明確的提交順序可跨 process exception／crash 找回；final 可還原時，命令檔已存在，原窗才可能被關閉。
- [x] 保存後各結果的命令找回路徑已實作；成功／失敗與 worker 存活警告有公開入口程序測試，取消狀態與 crash 另有 helper／子程序測試。保存後目視取消的完整 VM 路徑仍屬後續驗證。
- [x] 不以 `$suite.ExistingSnapshot` 的記憶體值、可遺失的 TEMP suite-result 或 stdout 解析作唯一復原來源。
- [x] 不會自動 Restore、執行 command text、覆寫舊 snapshot、重播測試或擴大關窗範圍。
- [x] 正常 exit codes、原 JSON、GUI safety／locks 與 safe default／import 均保持。
- [x] 代表性 IO／process 邊界／quote 測試及既有回歸通過；VM 正常提示順序與手動 Restore 已有截圖證據。§9 的完整 fault-point／host 矩陣及輸出順序自動斷言未全覆蓋，保留為後續驗證。
- [x] 文件清楚區分 worker crash 可提示與整個終端／系統消失只能靠持久檔案找回的範圍。

保存時的資料夾／分頁配置不等於完整工作狀態；正常 Restore 不保證選取、捲動位置、進行中的檔案操作或不支援 Shell namespace。BeforeSmoke 檔案可能包含私人路徑，維持使用者範圍，不提交原始 runtime 資料到 repository。本方案不另引入 ACL 管理、資料保留清理或自動還原功能。

實作、測試與驗收完成後再更新狀態；未達門檻不標記 Completed，也不將其他 Task-5 成功截圖當作本功能已驗證。


## 11. 實作結果與尚待驗證

已新增 Recovery helper、獨立 worker 及公開入口的前景 supervisor。S 路徑先捕捉並驗證 TEMP staging，再於 BeforeSmoke 先發布 descriptor／文字命令，最後以 final Snapshot 發布為提交點；日常 Snapshot 不變。suite.ExistingSnapshot 指向持久檔案。父程序以本次 RunId 找回，不依賴 worker 記憶體或解析混雜 stdout；子程序 handle 確認退出後顯示摘要，不自動 Restore。原 47 項 tests 保留斷言，僅為 synthetic adapter 加 RecoveryBase 指向 owned TEMP fixture，避免寫到真實使用者目錄。

新增 10 項 recovery 測試，驗證提交與覆寫拒絕、各 terminal status／缺少 suite result、hash 變動／缺失、其他 run 隔離、descriptor IO fault、引號 literal、真正前景 child 的正常 exit codes 與 Environment.Exit(17) 不執行 finally 時仍能提供復原命令。baseline 實跑 39／17／23／47／10，共 136 PASS、各套 Exit 0。產品及原 39／17 tests 未修改。

**尚未宣稱整份矩陣完成。** 無 GUI 程序邊界測試已通過；真實互動 Read-Host／Ctrl+C 在各 Windows terminal host 的行為、專用 VM 的 S→E01/E02→結束提示及人工複製 Restore 驗收尚待執行。完整 R01–R14／P01–P06 的每個 IO fault point 並未逐一注入；已有的核心覆蓋不等於所有列項全部驗收。BeforeSmoke 固定路徑／descriptor 目前以本次 GUID 與使用者 Known Folder 綁定，不增加另一份跨使用者復原機制。

本次沒有操作目前桌面的 Explorer、實際建立使用者 BeforeSmoke 備份或使用日常預設 Snapshot；所有新增測試都使用自行建立且經 ownership 檢查後清理的 TEMP fixture。不自動歸檔或 commit。

## 12. 後續 VM 清理交接修正

使用者以正常分頁重跑後，持久 Snapshot、完整命令與失敗後提示已出現，E01 Verify Passed，但在 E01-AutomaticClose 投遞前發生 CloseScopeChanged。提供的 before/after 截圖顯示根視窗、分頁路徑分組及 process fingerprints 相同，只有 COM Identity 指標改變。已補回歸先 red，再於清理交接依視窗指紋與完整分組重新取得 live observation，保留其 RCWs 至關窗完成；交接之後原 identity gates 不放寬。保存／supervisor 邏輯不因這次修復改寫。

目前離線五套 39／17／23／49／10，共 138 PASS。上述使用者 VM 結果支持保存及失敗提示，但整套仍未通過；新的清理交接與真實終端／Ctrl+C 驗收仍 pending，不標記 Completed。詳細證據與安全邊界見 ISSUE2-VALIDATION.md。

## 13. 使用者 VM 主要流程與還原命令驗收通過

使用者於 2026-11-03（client date）回報「通過了且也成功透過指令還原」，提供 `codex-clipboard-aad1bd8b-8e6f-4e64-bb5d-7b2fad699681.png`。畫面顯示 supervisor 的測試結果 Passed、整體 Exit 0，持久 Snapshot `3274dc4603a3417881d83823caf91b4c.json`、相同 RunId 的 restore.txt，以及已填妥 pwsh／工具／Snapshot 絕對路徑的 Restore 命令。使用者另行確認複製命令後成功還原；截圖本身沒有展示該 Restore 的 Report，不能自行推定 Verified 數量。

這次支持 §9.3 的正常互動 S→E01/E02→清理→最終提示，以及人工執行所顯示 Restore 命令兩項主要驗收通過；同時支持清理交接修正後能完成正常自動流程。先前 Failed run 保留作回歸歷史，不與本次 RunId 混用。

原始 JSON／hash、精確 VM Windows build／PS minor／執行 commit 未獨立取得；本地 review HEAD `3bc32b3` 不等於已驗證的 VM commit。仍未宣稱 Ctrl+C、所有 terminal hosts、保存後取消、整個終端消失及每個 IO fault point 已實機驗收。詳見[新版驗收紀錄](../../tests/Integration/TASK5-VM-ACCEPTANCE.md)。

本次只更新文件；主要功能已有使用者實機通過證據，不需要為這份紀錄再跑 E2E。完整延伸矩陣仍保留未完成標記，本計畫不自動移至 DONE 或 commit。

## 14. 結案驗收：未通過（review HEAD 78e2deb）

使用者要求驗收並於完成後歸檔。本次核對程式、測試與 VM 證據，發現 A01，故尚不符合結案條件；不以正常流程已通過代替錯誤處理驗收。

### A01 — P1 — 結果驗證失敗後仍可能顯示 Passed

- 位置：`tests/Integration/Start-ExplorerSmoke.ps1` 的 rawCode/status 分派與 catch。
- 觸發：worker 回傳 raw exit 0，但本次 suite-result 缺失、JSON 無效或 Status 並非 Passed。
- 原因：入口先把 `$status` 設成 Passed，再驗證 suite-result。驗證 throw 後 catch 僅設 `$code=1`，除 WorkerStillRunning 情況外沒有重設 status。因此存在有效備份時，復原摘要可顯示 Passed，但公開入口實際回傳 1。
- 已重現：複製原公開入口至 owned TEMP fixture，僅 stub worker return 0、suite-result 缺失及提示接收器。實際輸出 **NoticeStatus=Passed、PublicEntryExit=1**。沒有操作 Explorer、建立真實 BeforeSmoke 資料或修改 runner／tests；fixture 已安全清理。
- 違反條件：§5.3「不可只因 child raw exit 0 就宣稱 Passed」、§6.3 失敗不能改為 Passed、§9.2 P04 的 raw 0 但缺少合法結束結果不得偽報 Passed。這是核心結果呈現錯誤，並非單純的延伸 host 矩陣未完成。
- 修復要求：只在合法本次 suite-result 驗證成功後設 Passed；catch 將結果設為 Failed／結果不明，保留原始錯誤、WorkerStillRunning 提示與既有 Snapshot 的還原命令。不得以隱藏復原提示規避。
- 必要回歸：以公開入口邏輯覆蓋 raw 0＋missing／malformed／Running／Failed result，以及合法 Passed result；失敗案例一律不能顯示 Passed，已保存配置仍須顯示還原入口。現有只直接呼叫 helper 並傳入正確 status 的測試不足以攔住此缺陷。

持久保存、提交順序、獨立檔案、不覆寫日常 Snapshot、命令 quoting、正常 VM／手動 Restore 的既有成果仍成立。完整 IO fault／Ctrl+C 矩陣亦尚未全驗證；本次以已確實重現的 A01 判定暫不結案。修復摘要判定可先使用無 GUI 的回歸，不需要為本次驗收在工作桌面重跑 Explorer。

本次只進行驗收與記錄，不擅自修改 production code 或既有測試；未移動計畫、未 commit。

本次重新執行真正 baseline helper：39／17／23／49／10＝138 PASS，五套 Exit 0。A01 在這個全綠基準之外仍可重現，顯示公開入口錯誤路徑的測試缺口；不能以目前 suite 全過作為歸檔理由。

## 15. A01 修復與公開入口回歸（2026-11-04）

使用者授權修正後，先新增使用未改寫公開入口副本的程序測試，僅替換外部 worker／結果讀取依賴；格式化命令與持久復原提示使用真正 Recovery helper，所有檔案限制於 owned TEMP fixture。原版測試明確失敗：`A01 reproduced: Missing returns Exit 1 but displays Passed`。

修正集中於 Start-ExplorerSmoke.ps1：raw 0 時先標記結果驗證中，只有 suite-result 可讀且 Status Passed 才設成功；catch 一律重設 Failed／結果不明，再按 WorkerStillRunning 保留特殊警告。既有 JSON／原始 warning、非零 exit mapping、有效備份的完整 Restore 命令均保留，不改產品 Restore／Retry 或 Explorer 行為。

新增兩項測試分別覆蓋 missing／malformed／Running／Failed／Passed 結果，以及 raw exit 1／2／3／17 和 worker 仍存活的 catch 分支。負向案例要求公開入口 Exit 1、摘要不顯示 Passed、仍有完整 Restore 命令；合法成功保持 Exit 0。既有十項 recovery tests 未放寬。Recovery 10→12，五套實際基準為 39＋17＋23＋49＋12＝140 PASS（全 Exit 0）。

A01 已解除。此為結果判定與錯誤提示修正，沒有改動 GUI 操作，因此本次不要求重跑真實 Explorer E2E；既有使用者 VM 正常流程及手動還原證據保留。Ctrl+C／其他 host／完整 IO fault 點仍按原標記未全實測；本次不擅自將整份矩陣標為 Completed 或歸檔，不建立 commit。

## 16. Recovery 測試的非 UTF-8 輸出相容性（2026-11-04）

使用者 VM 的五套基準在 Recovery 顯示 0/12、Exit 1，E01／E02 未執行。公開入口 fixture 的 Missing 情境實際回傳預期 Exit 1 且保留 Restore 命令，但捕捉到的中文變成 `?`；測試以「測試結果：」定位摘要，因此 Summary 為空並在第一個斷言失敗。VM 改成 UTF-8 後原 12 項全過；本機明確設定 ASCII 亦能重現。這是新增測試的輸出編碼相容性缺陷，沒有證據指向產品 Restore 回歸。

修正僅在 `Invoke-SupervisorFixture` 的 native pwsh 輸出捕捉邊界暫設 `[Console]::OutputEncoding` 為 UTF-8，並以 finally 還原原編碼；不變更公開入口、產品行為、系統設定或原有斷言。新增一項回歸，分別在 ASCII／UTF-8 呼叫端驗證 Missing／Passed 的 exit、完整中文摘要、Restore 命令及編碼還原。新回歸於修正前先失敗，修正後通過；Recovery 12→13，baseline expected count 同步更新。

本機 PowerShell 7.6.1 的完整五套基準在預設及 ASCII 環境皆為 39／17／23／49／13＝141 PASS，全部 Exit 0；ASCII 執行完成後仍保留 ASCII 編碼。本機驗證當時，修正版 VM／真實 Explorer E2E 尚待使用者執行；先前 UTF-8 workaround 的 12 項通過未被當作新版驗收。不建立 commit。

後續使用者提供新的 VM 截圖：smoke 顯示 Passed／Exit 0，持久 Snapshot RunId 為 `c56cde9dad6a40c489fb61b49143b788`；使用同一 Snapshot 的手動 Restore 顯示 Completed／Verification Complete，4/4 Verified、0 Not verified。這補上一次主要流程與手動還原的使用者 VM 通過證據，詳見[驗收紀錄](../../tests/Integration/TASK5-VM-ACCEPTANCE.md)。截圖未顯示實際 commit、當次編碼或離線各套數量，因此不宣稱已在原非 UTF-8 條件下驗收修正，也不將其外推為重複可靠性或完整延伸矩陣通過。

## 17. 結案驗收與歸檔（2026-11-04）

**結論：核心實作與主要流程驗收完成，可移至 plans/DONE。** Review HEAD 為 `a3586fc`，不是已獨立驗證的 VM commit。本次核對 Recovery／Lifecycle／coordinator／公開入口／worker 及測試，未發現新的結案阻擋缺陷；不修改程式或測試，不建立 commit。

| 完成項目 | 證據與實際範圍 |
| --- | --- |
| 指定持久目錄、唯一命名、先保存後關窗 | Known Folder＋RunId 路徑；驗證 Snapshot bytes/hash 後發布；descriptor／txt 先於 final。Recovery 的 exact bytes／拒絕覆寫測試與 OneClick 的 Capture-before-close／失敗不關窗測試通過 |
| 不依賴 TEMP 結果或記憶體找回 | supervisor 以本次 RunId 定位 descriptor 與 final，核對路徑、V1 與 hash；缺少 suite result、final 缺失／變動、其他 run 均有測試 |
| 真實結果與異常提示 | A01 公開入口程序測試涵蓋 missing／malformed／Running／Failed／Passed、raw exit 1/2/3/17、worker 可能存活；另有真實子程序 Environment.Exit(17) 與保留已提交備份測試 |
| 命令與相容性 | literal quoting、正常程序 exit／中文參數、ASCII／UTF-8 輸出捕捉及編碼還原測試通過。保留既有 safe default／import、鎖、identity／scope gates；不執行產生的命令 |
| 本機離線基準 | 本次以 PowerShell 7.6.1、ASCII 呼叫端重跑真正 baseline helper：39/39、17/17、23/23、49/49、13/13，共 141 PASS，五套 Exit 0，結束後仍為 ASCII |
| 使用者 VM | 最新 smoke Passed／Exit 0；同一持久 Snapshot 的手動 Restore Completed／Verification Complete、4/4 Verified、0 Not verified，來源見驗收紀錄。非代理執行，不推定未顯示的 commit／編碼／逐套數量 |

結案採「核心契約的程式核對＋代表性離線回歸＋一次真實主要流程及手動 Restore」為範圍。§9 是較廣的設計測試矩陣，不把它全部勾成通過，也不再以其他 terminal host 的 best-effort signal 行為作為核心功能永久不得結案的條件。§10 因此明列實際證據層級；此為驗收範圍的明確化，不放寬程式安全閘或既有測試斷言。

設計與實作差異亦明列：descriptor 採 Version／RunId／Snapshot／SHA256／Validated／SuiteRoot 的最小內容，未加入 §4.2 原先預計的額外稽核欄位；使用者範圍 Known Folder 與本次 GUID 已提供現行復原定位，額外 metadata 非核心找回所需。自動產生的是 Restore 命令；Preview 可由 SOP 手動執行，並非本次必備輸出。

仍未完成的項目移交 [Backlog](../../Backlog.md)「持久還原延伸驗證」：保存後取消的完整公開入口／VM 串接、各 host 的 Ctrl+C／wait 中斷／終端消失、逐一 IO fault 與 checkpoint／serialization／提示失敗組合、輸出順序與特殊字元精確傳輸的完整斷言、重複可靠性及 VM commit／編碼追溯。原 R01–R14／P01–P06 保留為後續檢查清單；不以歸檔宣稱以上皆已驗證。BeforeSmoke 的不覆寫、不自動 Restore／刪除與失敗保留現場契約持續有效。

歸檔後新增批次中斷截圖：當次離線五套共 141 PASS、全 Exit 0；選 S 保存 Snapshot `d45f6e278e5a4aa182338f71d81608a2` 後，仍顯示「程序異常結束／結果不明」與同次完整 Restore 命令，畫面另有 Terminate batch job／^C。這補上 F02 的部分實機提示證據，不代表 worker 已退出、當次 E01／E02 或完整 Ctrl+C 矩陣通過；F02 保持 Open，細節見驗收紀錄。
