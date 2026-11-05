# Resume Explorer — Task-1 自動化測試：實作與結案驗收紀錄

- 初版日期：2026-11-01；本次重訂：2026-11-04。
- 狀態：**Done／本階段實作與主要流程驗收完成（2026-11-04）**。依使用者要求歸檔至 plans/DONE；結案判定見 §16，實作及使用者驗收證據見 §14–15。§1–15 中的規劃、待辦與中間狀態保留為歷史脈絡，以本狀態及 §16 為準。
- 規劃 Review HEAD（歷史）：e146f85；當時僅更新文件。結案 Review HEAD：a96ae8c；本次重跑公開離線入口並核對 JSON／logs，未執行真實 Explorer。
- 對應：[Backlog Task-1](../../Backlog.md)、[目前測試說明](../../README.md)、[Task-5 VM 證據](../../tests/Integration/TASK5-VM-ACCEPTANCE.md)。
- 本文件取代舊版要求先採 Pester／抽 Module／建立 Unit+Integration 統一 dispatcher 的實作順序。舊版 review 的歷史判定見 §13；後續以本文件的範圍、契約與完成標準為準。

## 1. 本次 Review 結論

Task-1 的原始目的，是提供可重複、安全且有診斷價值的自動化驗證。現有五套測試已保護不少局部行為；下一步應補實際缺口，沿用可用的基礎。

| 已核對位置 | 現況與判斷 |
| --- | --- |
| [產品 core](../../resume-explorer.core.ps1) 的 Read-Snapshot／Save-Snapshot／Start-RestoreRun（本次 L360／367／539） | 已有可載入的函式邊界；Restore 先讀 Snapshot 才建立 adapter，可測無效輸入是否在 UI 前拒絕。無須先重構 Module |
| [Issue2 tests](../../tests/Issue2.Tests.ps1) L291–309 | 一項實際 Save／Read／Preview 測試涵蓋兩組、重複路徑與 Preview hash 不變；尚未完整涵蓋空資料、單元素、UTF-8 及錯誤輸入的副作用邊界 |
| [baseline helper](../../tests/Integration/ExplorerSmoke.OneClick.Core.ps1) L6–18 | 已用獨立 current-engine processes 核對 exit 與精確 PASS 數量，零測試不會通過，並回傳 Suite／Passed／ExitCode rows。缺的是方便的離線入口與可查閱的失敗證據，不是完全沒有 runner 或結構化結果 |
| 同一 helper 的失敗處理 | 原始子程序輸出只存於區域變數；外層只見 OfflineBaselineFailed，這次編碼 regression 的診斷因此多次往返。應保留原始輸出與環境資訊 |
| [Recovery fixture](../../tests/ExplorerSmoke.Recovery.Tests.ps1) L52–62 | 暫用 UTF-8 捕捉 native pwsh 輸出、finally 還原呼叫端編碼，已有 ASCII／UTF-8 回歸；新 collector 應沿用這項已驗證契約 |
| Task-5 | E01／E02、整窗關閉及持久復原主要流程已有使用者 VM 證據；不重建另一個 E2E runner，也不把離線 green 當成 VM 通過 |

既有離線基準為 **39＋17＋23＋49＋13＝141 PASS**；來源是本 chat 前次實際執行，非本次新增執行結果。已確認該次 review 後的 PowerShell 程式／測試沒有變更。這個數字不能代表所有 Snapshot 契約已被覆蓋。

## 2. 採用方案與不做的工作

| 選項 | 決策與理由 |
| --- | --- |
| 沿用自訂 Test／Assert、core 與 adapter | 採用；保留既有回歸，新增獨立 Snapshot suite |
| 共用 suite manifest／collector，加薄的離線入口 | 採用；避免獨立 runner 與 smoke baseline 維護兩套數量／執行規則 |
| 直接複製 baseline helper 到新入口 | 不採用；編碼、錯誤與 expected counts 容易再次分歧 |
| 本次遷移 Pester、抽 src Module、重寫原五套 tests | 延後；目前缺口不需要框架遷移即可補齊 |
| 增加 Integration dispatch／新的 GUI 授權參數 | 不納入；使用既有 Task-5 入口與安全 gates |
| 建置 CI、coverage 百分比門檻、NUnit/JUnit exporter | 後續選用；本階段只定義小型 test-run JSON 與完整文字 log |
| 強化產品 Snapshot schema、實作 Task-2／FR-10 | 另案；本次測試不默認批准產品相容性變更 |

依賴政策：Windows PowerShell Core 7，使用當前程序的實際 engine，無新增第三方模組／安裝步驟；不要求 5.1。7.4.22 與 7.6.1 是已觀察到的環境，不代表所有 PS7 minor 都已驗證。環境不符時，離線入口回傳明確錯誤，不回退 powershell.exe 或偷偷安裝 Pester。

## 3. 範圍與相容性底線

- 新增內容以 tests 與文件為主；本計畫不預排產品 CLI／core 變更。測試發現真實缺陷時，先記錄重現、相容性影響與修復範圍，再處理，不改測試迎合錯誤。
- 保留原五套的斷言、順序及獨立 process 隔離；新增數量以實際 cases 為準，不先虛構未來 PASS 總數。
- 保留 Invoke-SmokeOfflineBaseline 的 fail-fast、成功 rows 的 Suite／Passed／ExitCode 欄位、OfflineBaselineFailed:<file> Reason，以及既有 suite-result／產品 Report／Snapshot schemas。
- 新報告是測試執行證據，不是產品 Report，也不進入正式 Runs／BeforeSmoke 或 FR-6 清理範圍。
- 真實 Shell COM、UIA、Explorer 啟閉與 Restore／Retry 只屬既有 opt-in E2E 流程；新離線入口沒有呼叫它們的路由。
- 不要求 Issue-4、Task-2、Task-3、FR-10 或 Task-5 全部延伸矩陣先完成，才可結案本階段。

## 4. Snapshot 契約：先測既有支援行為

目前 Read-Snapshot 只檢查 Version 比較、Windows 非 null、各 group.Paths 非 null，並由檔案／JSON parser 處理讀取失敗。舊提案的「嚴格整數 Version」「只接受 array 型別」「CapturedAt 必填」超出現行實作，**不是本次新增測試可直接要求的產品規格**。

先測正常 V1 writer 會產生的資料及現有明確拒絕條件。其他寬鬆接受情況先記為政策待決，不把它寫成永久相容保證，也不在本次默默改為拒絕。空陣列的斷言必須檢查 null 與 Count，不可用 PowerShell truthiness 將合法空集合當成失敗。

**補強既有 Capture 安全不變條件**：`Save-Snapshot` 遇到 `IdentitySetReliable=$false` 會在檔案寫入前拒絕；必須用既有 Snapshot sentinel 與尚不存在的目標檔雙重驗證「未覆寫／未建立」。但現行成功路徑使用 `WriteAllText`，不是原子 Snapshot 提交；不得把 observation 失敗的保護測試誤稱為寫入中斷也安全，後者需另案規格與修復證據。

新增 tests/Snapshot.Tests.ps1；以下是覆蓋群組，實際 Test 數量於實作後確定：

| ID | 情境與必要斷言 |
| --- | --- |
| S01 | 載入 core 不 dispatch Action／建立 Shell／UIA 或寫入使用者資料；測試先驗證 side-effect spy 確實可攔截，不允許 mock 失效後走真實平台 |
| S02 | Capture 零可保存 views：JSON 的 Windows 是空 array，Save／Read 成功 |
| S03 | 一窗一路徑：原始 JSON 及 roundtrip 的 Windows／Paths 保持 arrays，不退成 scalar |
| S04 | 兩組及多組、同組／跨組相同 Path：以 group/path multiset 驗證，不去重、不要求目前未保證的 tab 順序 |
| S05 | 存在的 Unicode／空白／單引號／& 目錄，實際 Save／Read UTF-8 roundtrip 原樣保留；資料中的 $() 等字元不被求值 |
| S06 | `PathReadable=false`、非目錄與不存在路徑的既有過濾行為，及 `IdentitySetReliable=false` 時 Save 拒絕且不建立／覆寫 Snapshot；不把這項測試當成 Shell namespace 支援或 FR-10 已完成 |
| S07 | Read 合法空 Windows、空 Paths：資料可讀，測試不擅自新增 skip/status 規格 |
| S08 | 檔案不存在／用 FileShare.None 建立的可重現讀取阻擋、壞 JSON、Version 缺失／不支援、Windows null／缺失、group.Paths null／缺失：核對既有拒絕條件，不依賴機器 ACL；檢查 PS7 對 missing property 的現行行為，不增加新 schema 限制 |
| S09 | 對 S08 代表性輸入呼叫真正 Start-RestoreRun，以會計數並 throw 的 adapter／report-initialization spies 證明 UI 與後續寫入邊界未被觸及；spies 必須先獨立驗證攔截有效，測試只以明確 sandbox ReportPath 執行 |
| S10 | 公開 CLI Preview 使用明確 fixture Snapshot；成功與錯誤入口的 exit／診斷合理，輸入 bytes/hash 不變。注意目前 CLI 對錯誤未自行 `exit N`，應先量測子 `pwsh -File` 的實際 exit code，不假設具體值；測試 sentinel 放在 child 自有 TEMP，禁止碰真實預設 Snapshot |

使用唯一 owned TEMP、明確 Snapshot／ReportPath、合成 HWND／identity，finally 清理前驗證絕對路徑及所有權。測試函式替換必須限制於局部 scope 或獨立 process；既有 Issue2 的 Snapshot 測試保留。

## 5. 共用離線 collector 與 smoke 相容層

預計新增 tests/TestRunner.Core.ps1，僅包含安全載入的函式：

1. 單一明確 manifest：原五套的檔名／順序／expected counts 保留，再納入 Snapshot.Tests.ps1 及 TestRunner.Tests.ps1。不得用任意遞迴 discovery 把 Integration 入口算成測試。
2. 每套使用當前實際 engine、-NoProfile -NonInteractive -File 與分離的 literal arguments；路徑以 PSScriptRoot 定位，不靠 PWD／PATH 中的另一個 pwsh。限定 Windows／PS7；若目前 host 不是 `pwsh` 或 engine 路徑不可驗證，fail closed，不回退 5.1。
3. 暫設 Console.OutputEncoding 為 UTF-8，捕捉完整合併輸出，立即保存 LASTEXITCODE，finally 還原原編碼，包含 launch／capture exception。避免自行順序讀取兩個 redirected pipes 而產生 deadlock。
4. Passed 的必要條件為 raw exit 0 且觀察到的 PASS 行數精確等於正數 expected。PASS 只能使用既有 suite 的行首文字協定，並以子程序原始輸出行計數，不接受被截斷、空輸出或重複行補足；空 manifest、零 cases、數量過多／過少、全數 PASS 後非零 exit 都不能成功；不以最後一行或子程序 exit 0 單獨判定。
5. collector 回傳內部 execution records 與完整輸出，日誌與摘要透過明確層處理；不得讓 Write-Output 的診斷文字混入成功 rows。
6. 具有內部 fail-fast 選項；standalone 離線入口可執行完所有獨立 suites 以取得完整診斷，smoke 相容層必須維持首次失敗停止。
7. 不新增 timeout／殺程序策略。離線 suite 卡住時不宣稱完成，未產生本次成功結果不等於 Passed；這不是 COM hard timeout 的修復。

Invoke-SmokeOfflineBaseline 改成薄相容層，委派共用 collector；保留原成功表格、rows 與 Reason。失敗時額外顯示原始錯誤與保存的 log 位置，證據保存錯誤不得蓋掉原失敗。

suite manifest 為唯一 expected-count 來源，禁止自動從測試原始碼估算 expected、減少 expected／跳過失敗換取通過。更新為 141＋實際新增 cases，舊 141 為必須保留的回歸範圍。

## 6. 獨立入口與測試報告

新增 tests/Invoke-Tests.ps1，**只執行離線 suites**。預定用法（尚未實作）：

~~~powershell
pwsh -NoProfile -NonInteractive -File .\tests\Invoke-Tests.ps1
~~~

不新增 -Suite Integration 或 GUI opt-in 參數；E2E 繼續使用 tests/Integration/Run-ExplorerSmoke.cmd／Start-ExplorerSmoke.ps1。入口 dot-source 時只定義函式／載入 core，不開始測試或建立 log 目錄；正常直接執行則只跑離線 manifest。

- 每次直接執行建立新的 owned TEMP 證據目錄，保存 result.json 與逐 suite 的完整 UTF-8 log，成功／失敗都印出實際位置。第一版不提供任意測試路徑、可執行 manifest 或 report 覆寫介面。
- smoke 相容層至少在失敗時保留同樣格式的離線 log／結果；不改它對外回傳的 baseline rows 或 suite-result schema。
- JSON 使用獨立 Version=1，至少包含 RunId、開始／完成時間、實際 EnginePath／PSVersion／OSVersion、OverallStatus、E2E.Status=NotRun／Reason=OfflineOnly，以及各 suite 的 Name／Expected／ObservedPassed／RawExitCode／Status／Reason／LogPath。
- Row Status 區分 Passed、Failed、Error、NotRun。啟動失敗／未執行的 RawExitCode 為 null；fail-fast 後續 suites 為 NotRun，不能當成執行失敗或捏造 exit。
- 不從 Expected−ObservedPassed 推算 failed／skipped case 數；早停時多數 cases 可能根本沒執行。現有文字協定只足以證明 suite 級結果，報告需如實保留這個限制。
- 結果從未確認開始就預設非成功，全部檢查與必要 log／report 寫入完成才可發布 Passed／exit 0。採本次唯一新路徑，不可沿用舊成功報告；報告寫入失敗需非零並指出錯誤／已存在的 log。
- Exit 0：全部 suites 通過且報告成功提交；Exit 1：suite 執行後失敗／count mismatch；Exit 2：runner 的環境、manifest、啟動或證據保存錯誤。若同時存在，Error 優先；raw child exit 另存，不直接覆蓋成入口 exit。
- 這組 exit 只屬離線入口，不重定義 E2E 的 0/1/2/3。所有離線報告都明示 E2E NotRun。

## 7. Runner 回歸：測真正的程序邊界

新增 tests/TestRunner.Tests.ps1，使用 owned TEMP 合成 scripts 與內部依賴注入。此 suite 本身進入 manifest，但不得在其內再次啟動完整 manifest 而遞迴。公開入口測試可複製未修改的 entry、只替換其 collector／manifest 依賴，沿用 Recovery supervisor fixture 的方式，不在正式入口加入 debug bypass。

| ID | 必要情境與驗收 |
| --- | --- |
| T01 | 正常 exit 0＋正確 count；非零 exit；正確 count 後 throw／Exit(17) 仍失敗，raw code 保留 |
| T02 | exit 0＋零／不足／過多 PASS；提前 exit 0；缺檔、啟動失敗、空 manifest、expected 非正數均非成功 |
| T03 | fail-fast 不啟動後續 sentinel suite，後續 rows 為 NotRun；standalone collect-all 能保存多個獨立失敗 |
| T04 | 失敗 log 保留真正 error／stack／Unicode 輸出；必要報告／log 寫入失敗不可 exit 0，也不可用 stale result 偽報成功 |
| T05 | 從不同 PWD 啟動；engine／檔案路徑含空白、中文、單引號；arguments 不經 Invoke-Expression 或字串 shell 拼接 |
| T06 | ASCII／UTF-8 呼叫端；成功及啟動失敗時原編碼皆還原，captured 中文原樣；較大量 stdout／stderr 能完成、不 deadlock |
| T07 | 真正 entry 的 exit／report 狀態一致，dot-source 無執行；離線預設不存在 E2E dispatch／GUI 授權或測試視窗操作。隔離 fake HOME／TEMP 並驗證不變的 sentinel；禁止在既有工作桌面實測負向 GUI 行為 |
| T08 | smoke wrapper 保留原 rows、suite 順序、fail-fast 與 OfflineBaselineFailed:<file>；既有 baseline failure prevents all GUI 測試持續通過 |

小型 fixtures 驗證 gate 的「red」不等於產品存在缺陷；只在確實發現產品 bug 時建立修正前重現。禁止改舊測試數量或斷言來適配錯誤實作。

## 8. 分批實作與檔案範圍

| 批次 | 工作與檔案 | 接受條件 |
| --- | --- | --- |
| A：Snapshot 覆蓋 | 新增 Snapshot.Tests.ps1，沿用現有 core；整理 S01–S10 對照 | 新 cases 覆蓋真實 Save／Read／Preview／拒絕前邊界，原 141 項保持；若發現不明 schema 行為先記錄政策問題 |
| B：離線入口與證據 | 新增 TestRunner.Core.ps1、Invoke-Tests.ps1、TestRunner.Tests.ps1 | T01–T07；真實小型子程序與結果檔驗證，不只有 mocks；無真實 GUI |
| C：共用與相容整合 | baseline helper 委派共用 collector，單一 manifest 加入新 suites；必要時補 OneClick 的相容斷言 | T08、原 adapter／Reason／rows 保留；全部原有 suites＋新 suites 通過，ASCII 與預設編碼的邊界問題被驗證 |
| D：文件與目標環境驗收 | README、Backlog、Integration SOP、ISSUE2-VALIDATION、本計畫 | 實際 command／count／證據位置及未驗證環境明確；一次整批目標環境驗收後評估結案 |

A／B 可分開 review；C 必須以測試確認共同實作的整合，不只修改呼叫名稱。合理的小批 commit 可保存進度，完成一批可驗收變更再做目標環境驗收；不把每個中間 commit 都變成人工完整 E2E gate。

產品 resume-explorer.ps1／resume-explorer.core.ps1 預計無變更；若需要變更，提供具體失敗證據與最小修復後重新評估相應 E2E，而不是為測試目錄架構重構產品。

## 9. 驗證與證據交付

1. 本機執行各新 suite、公開離線入口及相容 baseline；核對結果 rows／實際 exit／報告檔與 log，不只看 PASS 總數。
2. 以內部 synthetic fixtures 驗證 ASCII／UTF-8、不同 PWD、路徑、失敗／零案例與 early exit；不反覆重跑整套測試來替代明確的邊界測試。
3. 本機現有 PS7.6.1 可執行；若未取得 7.4.22，標成未驗證。目標 VM 首先執行同一公開離線入口，留存環境與失敗 log，避免再以多輪截圖診斷。
4. 本批 C 若改到 smoke 的共享 baseline 路徑，於批次完成後沿用既有專用 VM 操作一次一鍵 smoke，核對新 manifest、保存／關窗／E01／E02／清理及 supervisor 結果。已有舊版成功不等同新版共享路徑已驗證；此為一次整合驗收，非每個 commit 的要求。
5. 只有 Snapshot／文件或未接入 smoke 的離線入口改動，不自動要求完整 GUI E2E；新增 GUI／identity／worker 行為則另按實際風險決定。
6. 目標證據至少包含 tested revision（可由操作者記錄，無 Git 時不可猜）、PS／Windows／terminal、命令、結果檔、原始 raw exit 與 suite/case roots。原始私人路徑資料留在 VM，不提交 repository。

這些工作提高 Snapshot 與程序邊界的覆蓋及 E2E 失敗可診斷性，不能保證 Explorer／COM/UIA 在所有環境都通過。

## 10. 更新後的 Definition of Done

- [x] S01–S10 有實際 cases 與對照，原五套回歸及 assertions 保留。
- [x] 真正 Save／Read 的空資料、singleton arrays、group/path multiset、UTF-8 與已定義拒絕邊界經驗證；未新增未授權 schema 限制。
- [x] runner／core import 無副作用；直接執行僅跑明確離線 manifest，不 dispatch E2E。
- [x] 單一 manifest／collector；smoke wrapper 的 rows／Reason／順序／fail-fast 契約有測試。
- [x] T01–T08 涵蓋真實 process exit、count、launch／寫檔錯誤、編碼、路徑與不遞迴的 runner 自測。
- [x] 每次執行的 JSON／logs 可診斷失敗；E2E NotRun 明示，缺失／不完整／舊結果不被判為本次 Passed。
- [x] 實際總基準為 141＋新增 cases，預期數與觀察數一致；不把未跑 cases 算 failed 或 Passed。
- [x] Windows PS7 依賴、公開命令、結果位置／exit、證據與本機／VM 驗證範圍寫入文件。
- [x] 本批涉及共享 baseline 的 VM 一次整合驗收有結果；未涉及 GUI 的中間批次不強求逐 commit E2E。
- [x] agent 未操作真實預設 Snapshot／正式 Runs／使用者 Explorer；不新增自動 Restore、replay、kill／Registry／policy 修改。
- [x] 結案 Review 確認本階段無必要工作剩餘；已依使用者要求更新 Task-1 狀態並歸檔，未要求／建立 commit。

Pester、CI、Module 遷移、完整 Task-5 延伸矩陣與其他功能的所有 R-cases，不再是本階段必須完成的條件。

## 11. 風險與處置

| 風險 | 處置 |
| --- | --- |
| 舊計畫被當成新 schema 規格 | 以 §4 的現有支援行為為基線；政策不明另記錄，保留相容性 |
| 抽共用 collector 使 smoke 再 regression | 先驗證 gate／程序邊界，再以相容 wrapper 接入；保留 schema／Reason 並安排一次目標驗收 |
| 測試輸出編碼再次遺失中文 | UTF-8 捕捉＋finally 還原，ASCII／UTF-8 回歸與原始 log 一併驗證 |
| 新 tests 本身污染真實資料／呼叫平台 | owned TEMP、literal paths、可驗證 spies、process／scope 隔離；不以 Unit 名稱代替隔離證據 |
| 只有通過數字、仍須人工追問錯誤 | 失敗記錄 expected／observed／raw exit 與完整 output；入口直印證據位置 |
| 框架工作掩蓋真實覆蓋缺口 | 以 S/T cases 與原失敗機制為驗收，不以框架名稱、測試總數或 coverage 百分比代替 |

## 12. 文件與相依項目

- 現有測試入口說明：[README](../../README.md)；本計畫中尚未實作的 command 不得寫成現成可執行功能。
- E2E 操作與證據：[一鍵 SOP](../../tests/Integration/ONE-CLICK.md)、[VM 驗收](../../tests/Integration/TASK5-VM-ACCEPTANCE.md)。
- 已完成的相關工作：[Issue-2](resume-explorer-Issue-2-fix-plan.md)、[整窗關閉修復](resume-explorer-Task-5-multi-group-close-regression-plan.md)、[持久 Snapshot／復原提示](resume-explorer-Task-5-persistent-snapshot-restore-guidance-plan.md)。
- Task-2／Task-3、Issue-4、FR-10 保持獨立；Snapshot 的部分 invalid-path 行為雖已在 core 中存在，也不等於那些獨立需求已全面驗收。

## 13. 歷史驗收與本次修訂依據

- 2026-11-01 初版以當時單檔工具及尚無測試為背景，提出 Pester／Module／Unit+Integration runner；這些 repo 現況及首選架構已過時。
- 2026-11-02 Task-5 已另案完成使用者 VM 最小 E2E，後續自動清理／整窗關閉／復原提示皆有獨立修復與證據。早期 77／91／126 項為各版本歷史，不是目前基準。
- 上次 review HEAD 5ad1d52 將 Task-1 判為部分完成並保留於 plans/；Snapshot 首批覆蓋與測試入口／結果交付仍有工作，此判定維持。
- 本次 review HEAD e146f85 修正該 review 的解讀：現有 helper 已有 count／exit gate 與結構化 rows，獨立 runner 的價值在易用性、共用實作與失敗證據；不是要重造一套測試框架。JSON 新增範圍縮為離線 test-run，不要求統一 E2E result schema。
- 此版本已明確選擇沿用輕量框架，重訂實作順序與 DoD；§1–12 為現在的工作方案，不需再依舊版 Pester／src 目錄範例執行。未實作、未新增測試執行或 VM 通過聲明，也未建立 commit。

## 14. 本階段實作與驗證（2026-11-04）

本批以 `9e5325f` 為基底，在未提交工作樹實作 A／B／C 及 D 的本機部分。產品 core／CLI、原五套 tests、Snapshot／Report／suite-result schemas 未修改，沒有新增依賴或操作真實 Explorer。

| 檔案 | 實作／案例對照 |
| --- | --- |
| `tests/Snapshot.Tests.ps1` | 18 cases，名稱含 S01–S10。先驗證 platform spies 再 import；真正 writer／reader、空集合、singleton arrays、2／3 groups multiset、UTF-8 特殊字元、過濾與拒絕前保護；missing property／FileShare.None；真正 Restore 先拒絕、adapter／report spies 不被呼叫；公開 Preview 使用 child TEMP sentinel。實測壞 JSON／missing 的 pwsh -File 非零（本機為 1），不新增產品 exit 契約 |
| `tests/TestRunner.Core.ps1` | 唯一 manifest／collector、當前 Windows PS7 engine、UTF-8 捕捉並還原、raw exit／精確且無重複 PASS 行 gate、collect-all／fail-fast、四種 row statuses。logs 全部關閉，再以 `.partial` → `result.json` 發布完整摘要；不覆寫舊檔。manifest 錯誤盡量保存 Error 報告，證據錯誤不重試或覆蓋原錯誤 |
| `tests/Invoke-Tests.ps1` | 公開離線入口；dot-source 無 dispatch，唯一 owned TEMP 證據目錄；exit 0／1／2 與 E2E NotRun 說明見 README |
| `tests/TestRunner.Tests.ps1` | 16 cases，名稱含 T01–T08；真正 child exit／throw、零／不足／過多／duplicate PASS、early exit、缺檔／launch／manifest errors、fail-fast NotRun JSON、collect-all、原始錯誤／UTF-8 log、ASCII／UTF-8、6000 行 stdout／stderr、不同 PWD、特殊字元 script／engine 路徑（owned junction）。複製未修改 entry/core、替換依賴測 exit/report、log／report 真實 IO fault、stale result、import；不遞迴跑完整 manifest |
| `tests/Integration/ExplorerSmoke.OneClick.Core.ps1` | baseline 委派共用 collector，維持首次失敗即停及 Suite／Passed／ExitCode rows／Reason；失敗印原始輸出與證據位置 |

測試開發時確認：即使 `-NoProfile`，PS7 自身也會在隔離 LOCALAPPDATA 建立 `Microsoft/PowerShell` startup／telemetry 檔案。因此 fixture 改以未變 sentinel、沒有產品 ResumeExplorer 資料及沒有 dot-source run 目錄驗證安全；原五套 assertions 未改。Snapshot schema 寬鬆政策、原子 Snapshot 寫入與其他 Task／FR 保持另案。

實際環境：Windows NT 10.0.22631.0、PS7.6.1，agent PowerShell native-process capture，非互動式 Windows Terminal／VM 認證。驗證結果：

- `pwsh -NoProfile -NonInteractive -File tests/Snapshot.Tests.ps1`：18 PASS，Exit 0。
- `pwsh -NoProfile -NonInteractive -File tests/TestRunner.Tests.ps1`：16 PASS，Exit 0，含後補 stale result、真實 log／report IO 故障及 Error report 驗證。
- `pwsh -NoProfile -NonInteractive -File tests/Invoke-Tests.ps1`：39＋17＋23＋49＋13＋18＋16＝**175 PASS**，七套 raw exit 0、入口 Exit 0、OverallStatus Passed／E2E NotRun。證據：`%TEMP%/ResumeExplorer-OfflineTests-ffd1423fc7a14708a98f296e836e1428/result.json`（首次整合，後續再補 staging 及負向 assertions）。
- 最終程式的 `Invoke-SmokeOfflineBaseline`：ASCII 呼叫端、PWD 切至 TEMP，**175 PASS**，七列 rows 正確、raw exit 均 0、外層 Exit 0，呼叫端仍為 ASCII。使用相同 collector／報告 formatter，此輪含最終 staging 與故障 assertions。證據：`%TEMP%/ResumeExplorer-OfflineTests-f355102a35c74a15862133f144b01d9b/result.json`。
- `git diff --check` 通過，只有既有設定的 LF→CRLF 提示。原始 logs／本機私人絕對路徑不提交 repository。

實作交付時的剩餘驗收（後續結果見 §15）：在原專用 Win11 VM 先執行公開離線入口，再執行一次既有一鍵 smoke，核對新 manifest、S 保存／關窗、E01／E02／清理與 supervisor 結果。記錄 tested revision（本次無新 commit）、PS／Windows／terminal、命令、suite/case roots、result.json 與 raw exits。7.4.22 未取得，標為未驗證；既有 VM 證據不適用此批，未在工作桌面執行 GUI 負向測試。Task-1 不標 Done、不歸檔、不建立 commit。

## 15. 使用者新版整合驗收（2026-11-04）

使用者先提供 CMD 離線入口截圖：七套 39／17／23／49／13／18／16，共 **175 PASS**，各 suite raw exit 0、Offline Passed／E2E NotRun、launcher Exit 0；再提供新版一鍵 smoke 最終畫面：**Passed／Exit 0**，顯示本次持久 Snapshot 與完整 Restore 命令。依已核對的成功 gate，支持共享 baseline、E01／E02 驗證與清理、supervisor 的一次主要流程整合驗收；smoke 截圖未直接顯示逐 case rows，故這部分是依成功 gate 推論。使用者後續提供 `codex-clipboard-1b4477b1-2fd0-4edb-9e08-0e0714e9b697.png`，顯示執行同一份測試前 Snapshot 的 Restore 命令，Report Completed、Verification Complete、Total 4／Verified 4／Not verified 0，補足本次手動還原通過證據。截圖未顯示 `$LASTEXITCODE`，不另外宣稱 Restore 程序的 raw exit。

截圖來源、Snapshot RunId 及證據限制見 [VM 驗收紀錄](../../tests/Integration/TASK5-VM-ACCEPTANCE.md#task-1-shared-baseline-user-integration-acceptance-2026-11-04)。agent 未讀取 VM 原始 JSON/log，精確 tested revision、Windows／PS minor／terminal 與 case roots 未提供；本機 HEAD 不套用為 VM revision。7.4.22 與延伸矩陣保持未驗證。此次只更新文件、不重跑 GUI／離線測試，Task-1 待結案 review，不自動歸檔或建立 commit。
## 16. 結案 Review 與歸檔（2026-11-04）

**結論：Done，符合本階段完成條件，依使用者要求移至 plans/DONE。** Review 使用本機 HEAD `a96ae8c`，開始時工作樹乾淨；不將此 revision 套用為 VM tested revision。

- 已核對 S01–S10／T01–T08、單一 manifest／collector、離線公開入口、CMD launcher、smoke 相容層與 §10 DoD，未發現阻擋本階段結案的問題。
- Git 比對 `9e5325f` 至 Review HEAD：產品 CLI／core 及原五套測試均未變更；`8658d43` 至 Review HEAD 的 collector／新 suites／smoke wrapper 亦無變更。原 141 項回歸與 assertions 保留，沒有以調整舊斷言換取通過。
- 本次重新執行 `pwsh -NoProfile -NonInteractive -File tests/Invoke-Tests.ps1`：**39＋17＋23＋49＋13＋18＋16＝175 PASS**，入口及七套 raw exit 均為 0。再次讀取 result.json 及七份 log，核對每套 observed／expected／實際 PASS 行一致、OverallStatus Passed、E2E NotRun／OfflineOnly。證據：`%TEMP%/ResumeExplorer-OfflineTests-1abdb5ee0391423298b7f0098012f731/result.json`，環境版本以該 JSON 為準。
- 共享 baseline 的主要整合驗收沿用 §15 使用者本批截圖：CMD 離線 175 PASS／Exit 0、一鍵 smoke Passed／Exit 0，以及同一持久 Snapshot 手動 Restore Completed、4/4 Verified、0 Not verified。本次沒有重新操作真實 Explorer。
- 文件狀態、Backlog Completed 分類、所有指向本計畫的 Markdown 連結及本計畫內相對路徑同步調整；不變更程式、測試、版本號或產品 schemas，不建立 commit。

PS7.4.22 未實測、VM 精確 Windows／PS／terminal／tested revision 及原始 JSON 未取得，仍是已記錄的相容性／證據限制。依 §2、§3、§9 與 §10，本階段接受已驗證 PS7.6.1 及使用者本批主要流程證據，不宣稱所有 PS7 minor 或所有環境通過；這些限制不列為未完成的必要實作。Task-5 延伸重複／取消／故障矩陣仍由 Backlog 原項目追蹤，Pester／Module／CI、Task-2／Task-3／Issue-4／FR-10 仍屬獨立工作，未因本次歸檔被標為完成。