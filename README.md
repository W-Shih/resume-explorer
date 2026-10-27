# Resume Explorer

輕量的 Windows 11 File Explorer 視窗與分頁（Tabs）備份／還原工具，使用 **PowerShell、Shell COM 與 Windows UI Automation**，不需安裝第三方套件。

> **目前為實驗性版本**  
> 在一台 Windows 11 Enterprise 23H2（Build 22631）的 VMware Horizon VDI 上，已實測 `Capture` 和 `Restore` 可將 **2 個視窗、3 個 Tabs** 還原為原本的視窗／分頁分組。此結果不保證適用於其他 Windows 或 Horizon 版本。

## 功能

- **Capture**：讀取目前的 File Explorer 視窗及可辨識的資料夾 Tabs，按視窗 HWND 分組，寫入 JSON Snapshot。
- **Preview**：顯示 Snapshot 內容，並檢查其中的本機資料夾路徑是否仍存在。
- **Restore**：依 Snapshot **新增** Explorer 視窗，在對應視窗中新增 Tabs，再導向記錄的資料夾。
- 不使用全域 `SendKeys`、不修改 Clipboard、不修改 Registry、不更改 PowerShell Execution Policy。
- 不需要手動輸入 `OPEN` 或其他確認文字。

**尚未提供** `Restart` / 一鍵重啟 Explorer 功能。`Restore` **不會**關閉既有視窗，也**不會**終止 `explorer.exe`。

## 系統需求

- Windows 11（主要在 **23H2 / Build 22631** 環境驗證）
- Windows PowerShell（可使用 Shell COM 與 .NET UI Automation）
- 允許執行本機 PowerShell 腳本的公司／系統政策

在公司管理的 VDI 上，請遵守 IT 對 PowerShell 與自訂工具的規範；不要為了執行本工具繞過公司 Execution Policy。

## 安裝

將 `resume-explorer.ps1` 放到你選擇的資料夾，例如：

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
- [ ] Restore 後比對實際視窗／Tabs 與 Snapshot，提供成功／失敗報告。
- [ ] 加強 Tab 順序、目前作用中的 Tab 與視窗位置還原。

## 安全與合規

本版本沒有網路傳輸、Registry 修改、執行政策繞過或 `explorer.exe` 強制終止邏輯；**技術上沒有明顯危險**。
