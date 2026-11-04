# 一鍵 Explorer smoke — Windows 11 測試桌面

警告：測試會關閉 Explorer 視窗，可能影響目前工作。建議在可重設的 Windows 11 VM 或專用測試桌面執行，以降低干擾工作桌面或 VDI 的風險。需安裝 PowerShell 7，且 `pwsh.exe` 在 PATH。雙擊 `tests\Integration\Run-ExplorerSmoke.cmd`，或執行：

```powershell
pwsh -NoProfile -Sta -File .\tests\Integration\Start-ExplorerSmoke.ps1 -Run
```

Launcher 使用自身位置定位檔案，無須切換工作目錄。不要求系統管理員權限，也不繞過 ExecutionPolicy。沒有 `-Run` 或僅 dot-source 時，不列舉／關閉 Explorer、不建立 fixture，也不呼叫產品 CLI。

## 需要輸入什麼，以及為什麼

| 提示 | 用途與輸入方式 | 必填／可略過 |
| --- | --- | --- |
| 同意操作，輸入 `VM`／`TESTACCOUNT` | 聲明目前是專用測試桌面，並授權關閉既有視窗、建立及清理測試視窗。VM 輸入 `VM`，專用測試帳號輸入 `TESTACCOUNT` | 必要；Enter 取消，尚不執行 runtime／GUI 操作 |
| 環境備註 | 可填 `Win11-TestVM / clean-snapshot` 等實際資訊，方便日後追溯。電腦、SID、session、desktop 自動記錄；備註不是 VM 認證，也不要求外部批准編號 | **Optional，可直接 Enter**；VM 沒有快照可不填快照名稱 |
| 既有 Explorer 視窗的處理方式 | 顯示視窗與分頁數。`S`：先保存配置再關閉並測試；`C`：不保存直接關閉並測試；Enter：取消且不關閉 | **僅有既有視窗時詢問**；取消後不開始 E01 |
| `PASS` | 只在選用 `-RequireVisualReview` 時出現；實際檢查螢幕符合畫面上的條件才輸入 | 預設不詢問；選用目視模式後 Enter 會停止並保留 AwaitingVisualReview |
| 目視備註／截圖路徑 | 補充實際差異或證據。截圖路徑只是文字參照，不會自動擷取或驗證圖片 | **Optional，可直接 Enter**；仍記錄操作者已確認畫面上的條件 |

原本的 `CONTINUE` 和手動關閉 E01 步驟已移除；通過驗證後自動關閉本次測試視窗，再進入下一案例。不要把實際未觀察的內容填成目視通過。

## 執行流程

1. 取得上述一次 GUI 授權，檢查實際 PS7／Win11／STA／互動式 desktop 與 session。建立唯一 TEMP suite root，並取得同 TEMP 的 launcher 排他鎖。
2. 執行五套離線基準（39＋17＋23＋49＋13＝**141 項**）；失敗時不關閉任何視窗。
3. 獨立觀測既有 Explorer。已有視窗本身不阻擋測試；依你的 `S`／`C` 選擇處理。
4. 若選 `S`，以正式 CLI `Capture` 產生 `existing-snapshot.json`，核對與獨立觀測的視窗／路徑分組一致，重新確認原視窗未變。任何儲存失敗、不完整或過程中變更都停止，尚不關閉視窗。
5. 對明確授權且身分仍符合的既有視窗送出正常關窗要求，確認所有視窗已消失，再做空桌面 Preflight。
6. 建立獨立 E01 root，正式 CLI Restore 只執行一次，建立並核對 A|B、C 起始 fixture。setup Snapshot／Report 與案例自己的 Capture／Report 分開，任一未驗證項目都停止，不自動重試。
7. E01 執行正式 Capture → Preview → Restore。獨立 observer 核對 4 個可見視窗／6 分頁、原有分頁 identity／路徑不變、report fingerprints、分組與證據 hashes。
8. 預設以唯讀 `Verify` 再檢查 hashes 與即時 scope，通過後記錄案例 Passed、`VisualReview: NotRun`，自動關閉已驗證 E01 視窗並確認桌面清空。
9. E02 執行缺 B 的 Restore → PreviewRetry → 指定目標 Retry；核對父子 lineage、未改寫來源與原有 A、只在該視窗新增 B。以相同方式 Verify 並清理 E02 視窗。
10. 兩案例與清理均成功才產生整體 Passed／Exit 0。所有 evidence 保留，不自動 Restore 先前保存的配置。

獨立 observer 使用 Shell COM／Win32 觀測真實視窗，並與產品 report 比對，並非只相信產品自己的 `Verified`。UIA 目前檢查新增分頁能力，沒有完整核對畫面呈現；因此自動通過不代表人工目視已執行。

## 選用人工目視驗收

```powershell
pwsh -NoProfile -Sta -File .\tests\Integration\Start-ExplorerSmoke.ps1 -Run -RequireVisualReview
```

E01 檢查 4 個可見視窗／6 分頁：原有 A|B 與 C，另有還原的 A|B 與 C，原有分頁不變。E02 檢查 1 個 A|B 視窗，原 A 不變，只新增一個 B。每次 `PASS` 後仍執行原有手動 `Confirm` 的 hash／即時 scope 檢查；人工與自動檢查皆通過才記錄 `VisualReview: Passed`。取消目視時保留現場與證據，不清理該案例或進入下一案例。原[手動 runner](README.md) 也保留。

## 關窗、保存配置與停止條件

- 只關閉 Explorer 視窗，使用 `WM_SYSCOMMAND / SC_CLOSE`（系統選單的整窗關閉命令），**不終止／重啟 `explorer.exe`**，不關閉桌面與工作列，不處理其他應用程式。使用者 VM 已發現直接發送 `WM_CLOSE` 只減少一個分頁、視窗仍在，因此不再使用該訊息或以重複關分頁作 fallback。請先完成檔案操作；測試桌面執行中不要新增／操作視窗。
- 每個原 root／fingerprint 最多送出一次關窗要求；每次前重新觀測整個 scope、核對 identity、路徑、PID、process start time、session 與 HWND，原生發送前再次核對 fingerprint。**逐窗關閉：當前窗消失且取得兩筆相隔至少 200ms 的可靠一致觀測，才處理下一窗。** 已自行關閉的視窗不再操作；遇到已確認的新視窗、分頁變更或 HWND 重用立即停止，不擴大授權範圍。
- 測試視窗的清理清單來自驗證結果，路徑須屬本次 case root。測試失敗時不自動清理，方便調查；清理失敗則保留案例結果，但整體測試失敗，不進入下一案例。
- **每次關窗作業共用 10 秒預算**，從第一筆觀測前開始，包含全部目標及最後穩定空桌面檢查，不是每個視窗重新計時。既有視窗、E01、E02 各自是一次作業。已開始關窗後，暫時不完整／COM 與 Win32 不同步時只等待重新觀測，不向下一窗發送要求、不重送，也不把不可靠的空結果當成功。開始前觀測不可靠仍停止。
- 持續不可靠顯示 `CloseObservationTimedOut`；可靠觀測下原窗仍在則為 `ExplorerCloseIncomplete`。`Error.CloseSummary` 說明原定視窗數、確認消失數、未嘗試投遞數及紀錄位置；`Error.ExistingSnapshot` 保存先前配置路徑。可能已部分關窗，不要假設全部沒關。手動檢查殘留／對話框後另開新 run；不因 timeout 而殺程序。同步 COM／native 呼叫本身仍沒有 hard timeout 保證。
- Snapshot 僅保存工具支援的資料夾／分頁配置，不保存檔案操作、選取／捲動位置或所有 Shell namespace。若 Capture 遺漏 Home 等不支援路徑，完整性比對會停止並說明原因。可手動整理後重跑，或自行選擇 `C` 放棄保存；不默默降級成未備份關閉。
- 完整觀測失敗時，`existing-observation.json` 的 Errors 記錄原因；未知或未被 COM 曝露的視窗無法安全自動關閉。手動整理測試桌面後重跑。測試中 scope 不符的錯誤會說明實際視窗／分頁數及預期分組。

## 證據與結果

Suite root：`%TEMP%\ResumeExplorer-E2E-Suite-<GUID>`，包含 session-evidence、suite-result、既有視窗觀測、選用 Snapshot／驗證 hash、Capture stdout/stderr，以及 existing／E01／E02 關窗前後觀測與每次關窗嘗試。case roots 仍各自使用 `%TEMP%\ResumeExplorer-E2E-<GUID>`，保留既有 Snapshot／Report／Retry sidecar／hash／stdout/stderr。

每次關窗的 `<prefix>-actions.json` 保存固定目標 ledger：Planned、Posting、Posted、Closed、AlreadyGone、Failed 或 TimedOut，以及原始 fingerprints、分頁、Posted 布林值、最後 probe 狀態／錯誤。Posting 可能已進入 native 呼叫而未確認成功，不能重送。`<prefix>-observations.jsonl` 保留逐筆觀測、原 Errors／HRESULT、COM／Win32 roots 與唯讀 target probes，每行可獨立解析；最多 256 行。即使達上限，after JSON 與 actions 仍保存最後狀態。Posted 只代表成功投遞，不代表視窗已消失。

Exit codes：0 Passed；1 GUI 操作開始後失敗；2 未授權、取消或待目視；3 runtime／觀測／備份等前置條件阻擋。`suite-result.json` 的 `Phase`、`Reason`、`Error` 與 case statuses 可判別停止位置；自動模式的 `VisualReview` 明確為 `NotRun`。

如需稍後還原，先離開測試流程，再自行檢視與執行（以實際檔案位置替換）：

```powershell
pwsh -NoProfile -Sta -File .\resume-explorer.ps1 -Action Preview -Snapshot '<BeforeSmoke 中本次 RunId.json 的完整路徑>'
pwsh -NoProfile -Sta -File .\resume-explorer.ps1 -Action Restore -Snapshot '<BeforeSmoke 中本次 RunId.json 的完整路徑>'
```

排他鎖只防止同 TEMP 的一鍵 launcher／同 case 的 harness 並行，不排除手動或其他應用程式活動，也不取代產品 Task-3 的鎖。任何首次失敗即停止；舊 root 不 replay，新啟動使用新 roots。不要刪除使用中的 lock。證據含 SID 與私人路徑，請保留在 VM 並在分享前去識別化。

## 驗證範圍

原版一鍵流程已由使用者 VM 完成並關閉 Task-5；後續改用系統整窗關閉命令並補上訊息邊界測試後，**新版自動流程也已由使用者 VM 回報通過：Exit 0、Error null、VisualReview NotRun，並保存既有配置**。這個 NotRun 僅指未選用人工目視，並非自動測試未執行。原版及新版分開記錄於[驗收紀錄](TASK5-VM-ACCEPTANCE.md)。本次單次主要流程通過，不等於重複可靠性、額外分組或所有真實負向案例均完成；延伸 V01–V05 的剩餘項目見[修復計畫](../../plans/resume-explorer-Task-5-multi-group-close-regression-plan.md)，離線基準仍為 126 PASS。

## 持久 Snapshot 與還原提示

**核心實作與主要流程已完成（2026-11-04）**；[結案計畫](../../plans/DONE/resume-explorer-Task-5-persistent-snapshot-restore-guidance-plan.md)已歸檔，最新使用者 VM smoke Passed／Exit 0、手動 Restore 4/4 Verified。未全測的 host／取消／IO fault／重複可靠性項目保留於 [Backlog](../../Backlog.md)。

持久還原提示（核心實作與主要 VM 流程已驗收）：選 S 後，配置保存在 `%LOCALAPPDATA%\ResumeExplorer\Snapshots\BeforeSmoke\<RunId>.json`，同目錄有 `.recovery.json` 驗證紀錄及 `.restore.txt` 完整 PowerShell 7 還原命令。這些檔案在關窗前提交，不覆寫日常預設 Snapshot、不自動刪除或 Restore。前景 supervisor 等待 worker 結束後，在 JSON 後顯示還原提示；worker crash 時可依 RunId 找回，整個終端也被關閉時請查看持久命令檔。原有 suite/case 測試證據仍保存在 TEMP。目前有 13 項離線 recovery 測試，總基準為 39＋17＋23＋49＋13＝141；公開入口 fixture 捕捉子程序輸出時暫用 UTF-8 並還原呼叫端編碼，避免非 UTF-8 終端造成中文摘要斷言誤判。主要流程已取得使用者 VM 證據；驗收範圍與延伸缺口以驗收紀錄為準。

清理交接會先以完整 HWND／process fingerprint 及每窗路徑 multiset 核對驗收結果，再取得並持有目前的 COM references。驗收 JSON 中的 Identity 指標不作為後續物件生命週期的憑證；交接後關窗仍嚴格比對 live identity。交接前後觀測另存 E01/E02-close-handoff.json。這不改變產品 Restore／Retry 的候選識別規則，也不表示能跨程序證明同一分頁 identity。

持久還原提示的主要 VM 驗收已通過：使用者提供 supervisor Passed／Exit 0 的新截圖，並確認已成功使用顯示的完整命令還原配置。持久 Snapshot RunId 為 `3274dc4603a3417881d83823caf91b4c`，完整來源見[驗收紀錄](TASK5-VM-ACCEPTANCE.md)。這更新先前「正常互動與人工 Restore 待驗收」狀態；Ctrl+C、其他 host 與完整故障矩陣仍未宣稱實測完成。本次僅記錄結果，不改程式或重跑 E2E。
