# Task-5 — 多視窗關閉中斷：Review 與修復計畫

- 日期：2026-11-03。
- 狀態：**Implemented / Offline Verified / User VM smoke Passed（單次自動流程）**；延伸 V01–V05 矩陣尚未全覆蓋。保留於 `plans/`，不宣稱整份矩陣 Completed。
- Review 基準：`75477f3`（新增一鍵自動驗證與關窗流程）；本次開始時工作樹乾淨。
- 範圍：一鍵 smoke 的既有視窗關閉、E01／E02 fixture 清理、觀測診斷與回歸測試。
- 初始交付為 Review-only；使用者後續明確要求按計畫實施，已修改 harness／回歸測試及文件。產品、系統設定未改，不執行目前工作桌面的真實 Explorer 操作，不建立 commit。
- 關聯：[原 Task-5 結案計畫](DONE/resume-explorer-Task-5-powershell7-explorer-e2e-smoke-plan.md)、[目前操作文件](../tests/Integration/ONE-CLICK.md)、[驗證紀錄](../ISSUE2-VALIDATION.md)。

## 1. Review 結論

初次 Review 時，使用者回報「兩個 group 似乎只關閉一個」已有可重現的控制流程缺陷支持，並非只遍歷第一個 group。**後續使用者提供的正確 E01 觀測另證實直接 WM_CLOSE 只減少分頁、root 仍在的問題，見第 10 節。現行修復同時處理等待收斂與整窗命令選擇。**

目前確實逐一遍歷所有 `RootHwnd`，但送出第一個非同步關窗訊息後，立即重新做全域 COM／Win32 觀測。只要該筆觀測 `Reliable=false`，就立即拋錯，無法到達第二個視窗的關窗步驟。函式尾端的 10 秒輪詢同樣先拋錯，而且計時器要到全部關窗要求送出後才啟動，無法涵蓋這段過渡期。

建議採用**逐窗送出一次關窗要求，等待該窗消失且全域觀測恢復可靠，再處理下一窗**。保留原授權範圍、未知視窗拒絕、fingerprint 檢查及正常關窗方式；不靠忽略 Errors、重新發送 WM_CLOSE、固定 sleep 或終止程序修補。

原 Task-5 的舊版手動流程結案證據保留；本次控制流程缺陷已實作修正並離線驗證，**真實多組關窗尚未驗收**，不以舊紀錄宣稱已通過。

## 2. 已知事實、重現與未決問題

### 2.1 使用者 VM 證據

來源為本次提供的兩張截圖，圖片檔名分別為：

- `codex-clipboard-08429f67-ccd0-4cd2-b42a-4dd439eaee1e.png`
- `codex-clipboard-bd169494-0dce-4dd4-966f-13732b31eed4.png`

可直接確認：

1. 四套離線基準 39／17／23／23 均 Exit 0，共 102 項。
2. 啟動時偵測到 **2 個既有 Explorer 視窗、2 個分頁**；使用者選 `S`。
3. 畫面顯示配置已保存並核對，`ExistingSnapshot` 有值。
4. suite ID 為 `e3dc1b6f133d4da98dd02c9bfa002668`，Phase 為 `ExistingWindowsClose`。
5. 結果 `Failed`／`ExplorerObservationIncomplete`／Exit 1；E01、E02 均 NotRun，case roots 為 null，尚未開始測試案例。
6. 使用者觀察到只關閉一組。截圖沒有包含 actions／after 的原始內容，不能只依 terminal summary 判定實際發送次數。

**尚未取得或驗證：** 該次 `existing-close-actions.json`、`existing-close-after.json` 的 Errors、Win32／COM 各自的 root 清單、關窗過程的時間序列、VM 精確 build／PS minor／執行 commit。不可代入 agent 本機版本。

### 2.2 程式碼證據

| 位置（本次基準行號） | 已驗證行為／缺口 |
| --- | --- |
| [Lifecycle](../tests/Integration/ExplorerSmoke.Lifecycle.ps1) `Assert-SmokeClosable`，L3 起 | `Reliable=false` 一律立即 throw，沒有過渡觀測狀態 |
| 同檔 `Close-SmokeWindows`，L26 起 | foreach 按 RootHwnd 遍歷，並非固定只操作第一組 |
| 同檔 L31–43 | 每窗送出前 Observe → Assert；第一窗關閉中的不完整觀測可阻止第二窗收到關閉要求 |
| 同檔 L45–55 | timer 在 foreach 後才開始；輪詢內也立即 Assert，遇暫時不完整時沒有機會等待恢復 |
| [OneClick core](../tests/Integration/ExplorerSmoke.OneClick.Core.ps1) L22–27 | native adapter 用 PostMessage 發送 WM_CLOSE；成功只表示訊息投遞成功 |
| [Observer](../tests/Integration/ExplorerSmoke.Core.ps1) `Get-SmokeObservation`，L88–125 | 每筆 COM／fingerprint／path 例外都加入 Errors；COM roots 與另一次 Win32 枚舉不符也標為不可靠，兩者不是原子快照 |
| [OneClick tests](../tests/ExplorerSmoke.OneClick.Tests.ps1) L24–30 | fake close 同步移除整窗且下一次 Observe 立即可靠，未模擬非同步關窗過渡 |

Microsoft 文件確認 [PostMessage](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postmessagew) 不等待接收端處理完成；[WM_CLOSE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-close) 可由接收端先處理確認再銷毀視窗。因此 Posted 不能等同 Closed，也不能保證下一筆跨 API 觀測已一致。

### 2.3 本次無 GUI 的控制流程重現

載入現有函式；用記憶體 mock 取代 Observe、CloseWindow、Wait 與 Write-SmokeJson，未修改檔案、呼叫 native API 或開關視窗。預期集合為 root 10、20，每窗一分頁。

| 合成時序 | 實際結果 | 關窗要求 | 剩餘 root | Observe／Wait 次數 |
| --- | --- | --- | --- | --- |
| 每次觀測可靠 | Success | 10、20 各一次 | 無 | 3／0 |
| 第一窗關閉後一筆 `Reliable=false`，後續本可恢復 | ExplorerObservationIncomplete | 只有 10 | 20 | 2／0 |

第二列證實目前會在等待前就停止；它只證實控制流程缺陷，**不是重現了 VM 的真實 COM 錯誤**。合成錯誤採 `TopLevelExplorerAndComScopeMismatch`，VM 當時可能是其他例外。

本次另外執行現有 `ExplorerSmoke.OneClick.Tests.ps1`：**23 PASS／Exit 0**。這證實既有測試仍可全通過而未攔住此缺陷；沒有修改測試內容或重跑真實 GUI。其餘三套未在本次 Review 重跑，102 PASS 僅引用使用者截圖的該次基準。

### 2.4 優先級與根因可信度

- **P1／已證實：** 關窗流程把任何一筆過渡不完整觀測當終止錯誤，無等待恢復機會，會留下後續已授權視窗。既有關窗及 E01／E02 清理共用同一函式，均受影響。
- **P2／已證實：** `*-close-after.json` 反覆覆寫，只留最後樣本；actions 只有 Posted 布林值，無法區分 Planned、投遞中、已投遞、已消失、逾時等結果，現場分析不足。
- **P2／已證實：** 離線測試以同步刪除模型驗證了成功路徑，未涵蓋本次時間序列；102 PASS 無法排除此 defect。
- **待證實：** VM 的特定錯誤是已關閉 COM view、Win32／COM 暫時不同步、path 存取失敗，還是持續不可靠。須保留原 Errors，不把全部歸為暫時錯誤。
- **待排查：** 實際投遞數、root／raw 分組是否支援、視窗消失時其他 group 的 identity 是否改變，以及 WM_CLOSE 在該 build 的多分頁視窗行為。

## 3. 修復目標與不變條件

1. 支援零窗、單窗、多窗；一窗多分頁仍以 root window 為關閉單位，同一路徑存在不同窗不得合併成單一目標。
2. 以可信、已授權的起始集合固定目標，不隨新觀測擴大；既有視窗依 S／C 選擇處理，fixture 限本次 case roots。
3. 每個原始目標／fingerprint 最多投遞一次關窗命令（目前採 `WM_SYSCOMMAND / SC_CLOSE`）；同一數字 HWND 被重用不視為原目標，不重試關窗或替換成殺程序／SendKeys／COM Quit。
4. 不完整觀測可以在已開始關窗的階段**等待重新觀測**；等待期間不得向其他視窗送出關窗要求，不能認定空 scope 或宣稱成功。
5. 偵測到可確認的新視窗、原有未關窗分頁改變、PID／process start／session 改變等矛盾，立即停止後續發送。無法確認的錯誤只能在有限時間內等待，逾時停止，不能排除錯誤樣本後假裝乾淨。
6. 初始授權、Capture 完整性、Prepare／Run／Verify／Confirm 安全契約不放寬；產品 CLI、snapshot/report schema、正式 Runs 與 Restore／Retry 不改。
7. 最後須確認所有授權窗已消失，且完整全域觀測穩定為空，才能進入 Preflight／E02／Complete。fixture 的 case Passed 不代表清理或 suite Passed。

## 4. 方案比較與選擇

| 方案 | 判斷 |
| --- | --- |
| 固定 sleep 後繼續 foreach | 不採用；延遲不代表身分安全或已完成，慢 VM 仍失敗 |
| catch 所有錯誤繼續關其他窗 | 不採用；可能操作新／未知視窗，掩蓋真實觀測失敗 |
| 先對所有已保存 HWND 一次送完 | 不採用；繞過每次發送前的 scope／identity gate，縮小副作用前檢查不足 |
| SendMessage／SendMessageTimeout 取代 PostMessage | 不作主要修復；即使接收端返回也不等於 COM／Win32 已收斂，仍需觀測，且改變阻塞特性 |
| 全域 observer 任意忽略 WindowGone／scope mismatch | 不採用；會放寬 Capture／Restore／Retry 之外的 harness 驗收條件，範圍過大 |
| **依目標逐窗投遞一次，有限時間等待可靠收斂** | **採用**；修改集中 lifecycle；observer 只補診斷，原嚴格觀測語意保留 |

## 5. 詳細設計

### 5.1 目標清單與逐窗狀態

以起始可靠 observation 建立不可擴大的 ledger，每個 root 記錄原 fingerprint、原分頁 identity/path multiset，以及 Planned → Posting → Posted → Closed／AlreadyGone／Failed／TimedOut。Posting 必須先持久化再呼叫 native；發送例外或寫入失敗時停止，不在同一 run 重新送出。Posted 只是成功投遞，Closed 需後續證據。

在每次發送前保留全域可靠性與剩餘集合核對，並再次 native fingerprint 檢查。原窗已自行消失時記 AlreadyGone；若原 HWND 被重用則停止，不能將 replacement 當成可關目標。數字 HWND、路徑或目前的 group 排序不能單獨決定身分。

### 5.2 等待收斂，不重試副作用

1. 在第一筆關窗流程觀測前啟動單調計時；**整次 Close-SmokeWindows 共用 10 秒預算**，不隨窗數、錯誤或投遞重新起算。保留約 200ms 的 poll interval。
2. 取得可靠的起始 sample 並固定目標；預算內逐窗處理。
3. 當前 root 投遞一次後，先等待該目標原 fingerprint 的視窗消失，以及全域 observation 恢復可靠，才可發送下一 root。
4. 關窗過渡若出現 `Reliable=false`：記錄該樣本與原 Errors，等待下一筆；不呼叫原 Assert 把樣本直接升級為終止錯誤，也不把它當可靠 sample 使用。這項等待只存在於 lifecycle 的關窗收斂階段，不更動一般 Assert-SmokeClosable。
5. 新增唯讀 target probe：區分 Gone、原 fingerprint StillPresent、Reused／Changed；不可靠／例外不可映射為 Gone。Probe 與觀測均可 mock，native 使用既有 IsWindow／fingerprint 能力，必要時補同類型唯讀包裝。
6. 如可獨立確認未知 root、target replacement 或未關窗目標變更，立即停止。若觀測資料不足以判定，僅等待，不繼續副作用；預算耗盡回報觀測逾時。
7. 收斂判定至少需要兩筆相隔 poll interval 的可靠 observation，當前目標已消失且其餘仍是起始授權集合的合法子集；未發送目標須保留原 identity／path／fingerprint。全部處理完後，兩筆完整穩定空 scope 才成功，可重用最後等待階段的空樣本，避免多餘等待。
8. 每次觀測後、每次發送前、每次 wait 前檢查同一 deadline；同步 COM／CLI/native 呼叫本身無 hard timeout 保證，不宣稱可強制打斷。

不以錯誤文字 Contains 判定身分或完成狀態。錯誤種類可協助診斷，但成功判據仍是可靠觀測與 native target probe。若實際 VM 的錯誤使可靠觀測長期無法恢復，應停下來調查 observer，不持續擴充忽略清單。

### 5.3 時間與觀測依賴

增加 harness 內部的 elapsed-time／wait adapters，production default 使用 Stopwatch／200ms sleep，單元測試使用 fake clock 與排程 sample。這只服務 deadline 與時間序列測試，不建立 worker、service 或泛用重試框架，不新增產品公開參數。

observer 可加上 harness-only 的結構化診斷欄位：取樣序號／時間、COM roots、Win32 roots、EnumWindows 是否成功、exception 所屬階段及可取得的 RawHwnd／RootHwnd／HRESULT。`Reliable` 的定義不放寬；舊欄位保留。不得把 COM RCW 序列化到 JSON。

### 5.4 診斷與訊息

- 保留 `*-close-before.json`、`*-close-after.json`、`*-close-actions.json`，維持既有閱讀方式。
- 另外保存有界時間序列，例如 `*-close-observations.jsonl`：每個 poll／probe、可靠性、Errors、剩餘 roots、目標狀態與 elapsed time。約 200ms／10 秒的正常輪詢加上固定邊界事件，限制記錄量；不得無限追加。
- actions 每窗保留 Posted 與新狀態／最後觀測時間，區分已送未消失、未送即中止、已自行關閉，避免錯誤宣稱全部已關。
- timeout 區分 `CloseObservationTimedOut`（持續無法可靠觀測）與 `ExplorerCloseIncomplete`（可靠觀測下仍有原窗）；scope／fingerprint 變更保留獨立理由，發送失敗保存 native error。
- 提示範例：「原定關閉 2 個視窗；已確認關閉 1 個，尚未發送 1 個。等待 Explorer 觀測恢復可靠已達 10 秒，測試未開始。已保存配置：…；詳細 Errors／關窗紀錄：…」。數字須源自 ledger，不能從當前不可靠 Views 推估。
- 錯誤不得一律表示「未關閉任何視窗」；可能已部分完成。保留 suite Phase、E01／E02 狀態、Snapshot 路徑，不能以新的 summary 覆寫原始錯誤。

### 5.5 orchestration 整合

既有視窗、E01 清理、E02 清理共用新 lifecycle，避免只修啟動關窗。S 的 Capture 成功／hash 檔案保留；關窗等待不得重新 Capture、重跑案例、重播舊 suite 或自動 Restore。失敗保留現場與全部證據，不進入後續案例。整體 Exit 0 必須包含最終清理通過。

## 6. 實作順序與預計檔案

| 步驟 | 工作／檔案 | 驗證 gate |
| --- | --- | --- |
| A | 先保存使用者該 run 的 actions／after／observation／suite-result，對照第一窗投遞與首次 Errors；不可要求先重跑覆蓋現場 | 標記已證實機制及仍未知的 VM 原因；缺資料不阻擋補合成 regression |
| B | `tests/ExplorerSmoke.OneClick.Tests.ps1`：先加第一窗投遞後一次不可靠再恢復的時序測試 | 在原版 red：只投遞第一 root，第二 root 未送 |
| C | `tests/Integration/ExplorerSmoke.Lifecycle.ps1`：ledger、逐窗等待、共用 deadline、穩定完成判定、持久化 | 原 red 轉 green；每窗最多一次且無未知視窗關閉 |
| D | `tests/Integration/ExplorerSmoke.OneClick.Core.ps1`：唯讀 target probe／clock adapters、整合三個清理點及摘要 | 保存配置與無授權路徑不變；失敗不進下一階段 |
| E | `tests/Integration/ExplorerSmoke.Core.ps1`：只在需要時補結構化 observer metadata／序列化欄位 | 一般可靠性斷言及 Run／Verify／Confirm 行為不變 |
| F | 補完整測試矩陣；同步實際 baseline expected counts，不能為容納失敗而降數或略過案例 | 四套均 Exit 0，實際 PASS 數與 expected 一致 |
| G | 更新 `tests/Integration/ONE-CLICK.md`、`README.md`、`ISSUE2-VALIDATION.md`、`Backlog.md` 與本計畫狀態 | 說清總預算、等待與拒絕條件、新舊實機證據範圍 |
| H | 專用 VM 驗證及原始結果審閱 | 下列 VM 矩陣通過，才可稱多組關窗已修復 |

不需變更產品 `resume-explorer.ps1`／`resume-explorer.core.ps1`、產品版本或 Schema。原核心 39／17 測試應維持內容；harness 測試的必要變更須逐項記錄理由。

## 7. 測試矩陣與完整性要求

### 7.1 deterministic 離線測試

所有 GUI／target probe／time／wait 用排程 mock；native load-only 可獨立驗證，禁止測試時操作 agent 工作桌面。

| ID | 情境 | 必要斷言 |
| --- | --- | --- |
| C01 | 零視窗、單視窗、兩窗各一 tab、A|B 與 C、三組以上／不同窗重複路徑 | 每個原 root 各投遞最多一次；分組／路徑未合併；空集合零投遞 |
| C02 | 第一窗投遞後 1 次／多次不可靠，再恢復 | 第二窗直到觀測可靠且第一窗確認消失才投遞；最終成功；中間 Errors 可查 |
| C03 | Win32 先消失／COM 先消失、已關 view 例外、最後一窗過渡 | 不用不可靠樣本宣告成功；恢復後能結束 |
| C04 | 第一窗保持存在數個 polls 後才消失 | 等待而非重送；不提前操作下一窗 |
| C05 | 全程不可靠、原窗一直不消失、接近 deadline 才恢復 | 單調共用預算；不以每次 poll／每窗重置；原因正確，後續案例不執行 |
| C06 | 一次空 sample 後又出現已知／未知窗 | 不以單次空宣告成功；未知窗零投遞 |
| C07 | 新增未知窗／tab、未送目標路徑改變、PID／start／session 改變、HWND 重用 | 停止下一投遞；不擴大 expected；replacement 零關窗要求 |
| C08 | 原窗自行消失、投遞前最後 native probe 發現消失／重用 | 已消失目標不送；重用停止；不因剩餘排序改變跳窗或重複 |
| C09 | PostMessage 失敗、Posting／Posted 寫檔失敗、觀測／probe 拋錯 | 不重送；證據區分可能已送與未送；不得宣稱成功 |
| C10 | 初始不可靠、拒絕授權、S 的 Capture 失敗／不完整、取消 | 原有安全測試繼續有效；等待邏輯不繞過前置 gates |
| C11 | ExistingWindowsClose／E01 close／E02 close 各自套用 C02／C05 | 成功才進 Preflight／E02／Complete；case Passed、suite Failed 可正確表達 |
| C12 | diagnostic 序列化、紀錄上限、CLI default／import | 保留原 Errors／HRESULT／投遞順序；不輸出 RCW；無授權零觀測及關窗 |

現有同步成功模型不應全部刪掉；增加非同步排程模型作補充。原 unknown-window／identity／Capture／missing visual review／default tests 保留。`KeepWindows` 測試目前 Wait 直接拋 synthetic 例外，無法證明真實 deadline；新增 fake-clock timeout 測試替補這項缺口，但保留例外路徑覆蓋。不得將 `Reliable=false` 改為 true、放寬 scope assertion 或 skip 失敗來取得 green。

### 7.2 專用 Windows 11 VM

記錄實際 build／PS 完整版本／commit／session facts，使用可重設且無其他互動的測試桌面，逐次保留 suite/case roots，勿沿用舊 pending run。下列 live 結果不能由合成 PASS 代替。

| ID | 起始情境／操作 | 驗收 |
| --- | --- | --- |
| V01 | 原回報：2 個獨立單 tab 視窗，選 S；至少連續 3 次，以新 roots 執行 | Snapshot 完整保留兩組；兩窗皆關閉，Preflight 後 E01／E02 與最終清理皆成功 |
| V02 | 同樣兩窗，選 C；另驗證 Enter 取消 | C 能繼續；取消不關窗、不開始案例 |
| V03 | A|B 與 C、多組各多 tab、不同窗相同路徑 | 確認所有分頁隨所屬 root 關閉，不只作用於 active tab／第一組；scope 完整 |
| V04 | 沒有既有視窗啟動，讓實際 E01 的 4 窗／6 tab 與 E02 的 1 窗／2 tab 清理 | E01 全清才進 E02；E02 全清才 overall Exit 0；觀測序列可追溯 |
| V05 | 可控延遲／殘留，與測試中新開未知窗的負向測試 | 等待有界；未知窗保留，沒有殺程序；失敗不進下一案例且保留現場 |

V05 不以故意掛死 Explorer 或強殺程序製造條件；能 deterministic 模擬的異常不強求在 VM 製造危險狀態。必要時以安全殘留／人工新增 fixture 驗證停止行為，並如實記錄未實測子項。

## 8. 完成標準、風險與回退

- [x] 原控制流程 defect 有先 red 後 green 的 regression 證據（下節；不等於真實 GUI 重現）。
- [x] C01–C12 的適用子項已有離線覆蓋且四套回歸通過；expected count 依新增數更新。
- [x] 原 snapshot/report/Retry 與人工作業契約不變，native helper compile/load 通過。
- [x] 啟動及 E01／E02 清理均採同一修復；合成過渡樣本不再立即終止。
- [x] 離線驗證一筆不可靠或空 sample 不導致誤關或誤判成功；每原目標至多一次副作用。
- [x] ledger／JSONL／suite error 可追溯各目標、原 Errors、停止時間及 Snapshot 路徑。
- [ ] V01–V04 有新版本 VM 證據，V05 的安全負向驗證及未實測限制明確記錄。
- [ ] 文件、計畫狀態與實測範圍一致後才標記 Completed，依使用者要求再歸檔／commit。

殘餘風險：COM／Win32 仍非原子快照；同一進程內 COM identity 在特定 build 可能不穩定；同步呼叫可能超過預算；系統整窗關閉命令可能被應用程式延遲或拒絕。這些情況須停止並保留證據，不能以增加無限等待／重送／殺程序掩蓋。若證據顯示 observer 對穩定剩餘窗長期誤判，再另評估受控觀測修正，不能直接將所有不完整 sample 視為安全。

回退時保留目前所有 run、Capture Snapshot 與關窗紀錄，改用既有手動 runner／手動整理測試窗。已關閉的視窗無法藉程式回退自動復原；是否使用保存的 Snapshot Restore 由操作者另行決定，不在失敗處理中偷偷執行。修復不得干擾工作桌面的 Explorer。

## 9. 本次實作與驗證紀錄（2026-11-03）

實作基準為 `1862ba1`，開始時工作樹乾淨。未取得原 VM 的 private JSON；步驟 A 的原始錯誤歸因仍待資料，但不阻擋已證實機制的合成修復。沒有在 agent 桌面重跑案例或關閉視窗。

### Red → Green

先在 `ExplorerSmoke.OneClick.Tests.ps1` 新增 `multi-root close waits through incomplete observations and posts each root once`：兩 root 10／20，第一窗及最後一窗投遞後各兩筆不可靠 sample。未修改 lifecycle 時測試 **Exit 1 / ExplorerObservationIncomplete**；第一窗已進入 native mock，下一次 Assert 立即失敗。實作後該測試通過，斷言發送順序 10、20 各一次，第二次投遞不得早於 fake-clock 600ms；JSONL 保留四筆原始不完整觀測及 HRESULT=123，ledger 兩目標皆 Closed。

### 實際修改與相容性

- `ExplorerSmoke.Lifecycle.ps1`：固定 ledger、逐窗投遞／收斂、共同 deadline、兩筆穩定觀測、partial sample 的正向矛盾拒絕、持久化及失敗摘要。保留原嚴格 `Assert-SmokeClosable`，沒有將不完整結果改成可靠。
- `ExplorerSmoke.OneClick.Core.ps1`：Stopwatch／elapsed adapters、唯讀 Gone／StillPresent／Changed probe、發送前最後 gate、PostMessage 原生 error 保存、suite Error 附 CloseSummary／ExistingSnapshot，baseline expected 23 → 43。
- `ExplorerSmoke.Core.ps1`：僅加 harness observer 的 Stage／RawHwnd／RootHwnd 診斷與 COM／Win32 roots／EnumWindowsSucceeded 序列化；`Reliable`、Run／Verify／Confirm 判斷條件不變。
- `ExplorerSmoke.OneClick.Tests.ps1`：保留原 23 項斷言；adapter 改成明確 Posted outcome、fake elapsed／probe，正常 Wait 改為推進 fake clock，KeepWindows 的原 Wait 例外路徑保留。這些是新內部 adapter 契約及收斂等待需要的 fixture 變更，不是放寬測試。
- 新增 20 項 deterministic 測試（合計 43），涵蓋 C01–C12 適用子項；同一測試以多個排程覆蓋部分邊界，不以合成值宣稱 native GUI 行為已驗證。
- 更新操作 SOP、README、Backlog、驗證紀錄及本計畫；產品 CLI／core、原 39／17 測試、snapshot/report 格式均未改。無新 public CLI 參數或依賴。

### 離線結果與矩陣對照

| 項目 | 結果／覆蓋 |
| --- | --- |
| 真正的 `Invoke-SmokeOfflineBaseline`（PS7.6.1） | Issue2 39、RestoreSummary 17、Smoke 23、OneClick 43，**122 PASS，四套 Exit 0** |
| C01／C02／C03／C04 | 零窗／多 root 多 tab／重複路徑；過渡不完整；COM 與 Win32 兩種先後消失；延後消失、Observe 拋錯後恢復 |
| C05／C06 | 共用預算含觀測時間；原窗不消失；長期不可靠；fake 9800ms 成功／10000ms 不足兩筆穩定觀測則停止；單筆空後未知窗阻止成功 |
| C07／C08 | partial sample 出現未知 Win32 root；未送窗 tab 消失；原有 identity/path/PID/session/start 變更測試保留；probe Unknown／Changed；自行消失與 native 最後 gate 回 Gone |
| C09 | Post 失敗保留 error=5；Posting／Posted 寫入失敗不重送；Observe／probe 例外保留；原 Wait 例外路徑保留 |
| C10 | 原授權、預設、Capture 失敗／不完整、取消、初始不可靠與人工驗收 gates 全數保留 |
| C11 | 啟動、E01、E02 各測短暫恢復與長期觀測逾時；後續階段不執行，原案例結果／失敗 suite 正確保留 |
| C12 | JSONL/HRESULT、RCW 排除、256 行上限、prefix replay 拒絕、import/default 無副作用 |
| STA load-only | PS7.6.1，native helper 編譯、PostMessage 宣告及 UIAutomationClient／UIAutomationTypes 載入通過；不列舉 Shell、不做 target probe／發送 |
| V01–V05 | **NotRun／Pending**；agent 無專用 Windows 11 VM 互動桌面，尚無新版使用者實機證據 |

實作保留 10 秒整次作業預算／約 200ms 輪詢，JSONL 額外硬限 256 行；不因 history 達上限而抹掉最後 actions／after。同步呼叫仍無 hard timeout，已披露。最後 VM gate 未通過前，本 follow-up 留在 `plans/`，不稱真實多組關窗已驗收，也不套用先前 Task-5 的完成截圖。

## 10. 後續 VM 失敗證據與整窗命令修正（2026-11-03）

### 10.1 採用的證據與判斷

使用者明確撤回先前 `15:09:50Z` 的空觀測截圖。本節採新提供的 `codex-clipboard-28a8656d-06d1-4f26-b3db-8c88844344f0.png`（JSONL）與 `codex-clipboard-1f5c86f0-41a3-44b6-bbe7-ab6ff4adefff.png`（實際 E01 after），並對照先前該 run 的 ledger 截圖；未取得原 JSON、檔案 hashes 或精確 VM build／commit，不冒稱獨立解析完整原檔。

| 資料 | 可確認事實 |
| --- | --- |
| 起始 ledger | 4 個 root／6 個分頁；第一個目標 329616 原本是 A|B，Posted true，最後 TimedOut／StillPresent；另外三個 Planned |
| 最後觀測 | `2026-11-03T15:10:19.9361025Z`，Reliable true、Errors 空、EnumWindowsSucceeded true |
| COM／Win32 | 同樣四個 roots：329616、656102、918854、1050294；視窗沒有消失 |
| 最後 Views | 5 個分頁：329616 只剩 A；1050294 的 A|B、另兩窗 C 都仍在 |
| 結果 | E01 已走到清理階段，root 不消失導致 ExplorerCloseIncomplete／Exit 1，後續清理及 E02 不繼續 |

證據支持本次 VM 的直接 `WM_CLOSE` 作用於 active tab，沒有完成 root-window 關閉。上一輪已修正關窗過渡不可靠即中止，但本次是可靠觀測持續看到原窗的另一個缺陷；增加等待時間或忽略不消失目標都無法修正命令語意。V04 在舊 `WM_CLOSE` 實作上已有 **Attempted / Failed** 證據，不能繼續描述成從未執行；新命令仍 NotRun。

### 10.2 修正與 API 依據

以 `PostMessage(rootHwnd, WM_SYSCOMMAND=0x0112, SC_CLOSE=0xF060, 0)` 取代直接 `WM_CLOSE=0x0010`。Microsoft 的 [WM_SYSCOMMAND 文件](https://learn.microsoft.com/en-us/windows/win32/menurc/wm-syscommand) 定義 SC_CLOSE 為系統視窗關閉命令；[系統關閉路徑說明](https://devblogs.microsoft.com/oldnewthing/20190411-00/?p=102411) 說明標題列 ×／系統選單 Close 會先經過 SC_CLOSE。這支持改用整窗關閉路徑的設計，**仍不是該 Explorer build 的新版實機通過證明**。

只抽出小型 `Invoke-SmokeWindowClose` 邊界，使實際命令選擇可用 fake probe／post-or-throw transport 驗證；native adapter 委派給此邊界，保留最後 fingerprint gate、Gone 時零投遞、Changed 時停止、原生錯誤碼與每目標最多一次的契約。lifecycle 的 common deadline、兩筆穩定消失驗證及未知視窗拒絕不變。沒有重複關 tab、改用其他方法 fallback、終止程序或加長 timeout。

### 10.3 測試缺口與本次結果

先前 122 項測試的 fake CloseWindow 直接移除整個 root，沒有檢查原生 message/wParam，因此漏了訊息選擇問題。本次保留既有測試，另新增四項：

1. 真正 request selector 的 root／message／wParam／lParam 及單次投遞；先以原 `WM_CLOSE` 選擇執行，**Exit 1**，明確失敗於必須選 SC_CLOSE 的斷言；修正後通過。
2. selector 的 Gone／Changed／probe-error／transport-error 門檻與不重送，保存 native error=5。
3. lifecycle 接上真正 selector，以 VM 證據建立 fake transport：WM_CLOSE 只移除 B，SC_CLOSE 移除整窗。驗證兩組皆完成，每 root 一次；此語意模型不是實機證據。
4. 負向 tab-only close：root 仍在時不能記為 Closed、不能關下一窗或重送；10 秒後仍失敗並保留現場。

OneClick 43 → **47**，四套基準合計 **39＋17＋23＋47＝126 PASS，全部 Exit 0**（PS7.6.1）。更新 README／Backlog／SOP／驗證紀錄與 baseline expected count；產品、原 39／17 測試及 V1 report/snapshot 均未變。

此追加修正完成實作與離線驗證，**新 SC_CLOSE 版本的 V01–V05 仍待專用 VM**。下一次以新版一鍵入口取得 E01／E02 及清理結果，保留新的 suite/case roots；不混用本次失敗 run 或先前 Task-5 完成截圖，也不先刪掉現有證據。

## 11. 新版使用者 VM 自動流程通過（2026-11-03）

使用者更新後回報「通過了」，提供 `codex-clipboard-065782ae-c2c6-4e4a-a242-628f5fde06d3.png`。畫面顯示 OneClick 47／Exit 0、Error null、VisualReview NotRun、整體 Explorer smoke exit code 0，以及新 suite `68d2f08e58f5445ea0c5e4f5d8ba3781` 的 existing-snapshot.json。這取代「新版完全未實測」狀態，支持**單次自動整窗關閉／E01／E02 與清理的主要流程通過**。VisualReview NotRun 是自動模式正常結果，不偽稱人工目視已執行。

依已審閱 launcher 的 Exit 0 gate，兩案例自動驗證與清理均須成功才能取得此結果；屬程式控制流程與使用者報告共同支持的推論。截圖沒有直接展示 case status rows、各 close ledger／最後空樣本、初始視窗數與精確 VM 版本／commit；未重新解析原 JSON。詳細來源與範圍見[驗收紀錄](../tests/Integration/TASK5-VM-ACCEPTANCE.md)。

| 矩陣 | 更新後證據狀態 |
| --- | --- |
| V01 | 保存既有配置後執行整套流程通過；初始是否恰為兩窗、連續三次尚未證實 |
| V02 | 本次為 save 路徑，C／Enter 的真實 VM 路徑未由本次截圖證實；離線覆蓋保留 |
| V03 | E01 內建多窗／多 tab fixture 的自動流程通過；額外更多組與重複路徑未實測 |
| V04 | E01／E02 驗證與兩階段清理通過；本次有 ExistingSnapshot，不能代稱零既有視窗起始條件已驗證 |
| V05 | 真實 GUI 負向情境未由本次證據覆蓋；deterministic 停止／timeout／identity 測試仍通過 |

主要 regression 的新版 VM smoke 已通過，不再要求為同一份文件紀錄重跑 E2E。完整矩陣與詳細原檔追溯仍未全完成，因此不把所有 V 項目勾為 Passed 或歸檔成全面驗收。本次只更新文件，不修改程式、測試、版本或原始 VM 證據，不建立 commit。
