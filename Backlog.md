# Backlog

## Issues

### Issue-1

這種路徑沒有打開 "H:\fake-path\dummy.zip"

### Issue-2

```txt
PS C:\Projects\resume-explorer
λ & .\resume-explorer.ps1 -Action Restore
Group 1, HWND 1001 : C:\Users\Example\Documents\Project
  Requested new tab: C:\Users\Example\Documents\Project\Notes
  Requested new tab: C:\Users\Example\Documents\Project\Reports
  Requested new tab: D:\Data\Downloads
  Requested new tab: C:\Tools\ProcessViewer
Group 2, HWND 1002 : D:\Work\Learning\AI-Coding\Course\Module-1
WARNING: Group 2: Multiple new tabs detected; cannot safely choose one. Remaining tabs in this group skipped.
Group 3, HWND 1003 : D:\Personal\Projects\2026
  Requested new tab: D:\Personal\Projects\2025
  Requested new tab: D:\Personal\Projects\2027\Preparation
  Requested new tab: D:\Data\Downloads\Reference
Group 4, HWND 1004 : C:\Users\Example\Downloads\Shared\Work
  Requested new tab: C:\Users\Example\Downloads\Shared\Archive
Group 5, HWND 1005 : D:\Work\Projects\Design\Current
Group 6, HWND 1006 : C:\Projects\Tools\Output
Restore attempted. Inspect resulting tabs before considering a restart workflow.
```

Group 2 中有多個其餘標籤頁已被跳過, 是不是要引入 re-try 機制, 讓其嘗試一定次數後再放棄? 這樣可以避免因為暫時的問題而導致該 Group 後面的標籤頁無法正常打開。

若 re-try 後, 依然無法安全選擇一個標籤頁, 那麼就可以放棄該 Group 的其餘標籤頁, 並記錄下來以便後續手動 re-try 定同時指定欲加入 Group 的標籤頁.

## Feature Requests

### Feature Request-1

當執行 `& .\resume-explorer.ps1 -Action Restore` 時，希望在背景還原 Explorer 視窗與標籤頁，不顯示或彈出 Explorer 視窗、不將其帶到前景，也不搶走目前使用中應用程式的焦點，以免打斷使用者操作。

此需求針對 Explorer 視窗本身的顯示與焦點行為，不是僅隱藏 PowerShell／Console 視窗。

先記錄期望行為，不預設實作方式，也不因技術難度預先縮減需求。可行性與開發成本留待後續評估；若無法可靠達成或成本不合理，可記錄原因並將此需求標記為 Rejected。

### Feature Request-2

詢問是否將執行檔加入系統 PATH, 以便在任何目錄下都可以直接執行 `resume-explorer.ps1` 而不需要指定完整路徑

### Feature Request-3

當執行 Capture 功能時, 目前只會保留最後一次的標籤頁組合, 並會覆蓋掉之前的組合. 建議至少提供 2-3 個組合的保留, 以便使用者可以回溯到之前的標籤頁組合, 而不會因為覆蓋而失去之前的組合.

### Feature Request-4

將此功能整合進其他專案 `restart-win-explorer-scripts` 和 `restart-windows-taskbar`, 以便在重啟 Windows Explorer 或 Windows Taskbar 時, 可以自動恢復之前的標籤頁組合, 提升使用者體驗. 但不是單純複製貼上 src code, 注意 DRY 原則和 SRP 原則, 需要將共用的功能抽象化成模組或函式庫, 以便在不同專案中重複使用, 並且方便維護和更新.

## Tasks

### Task-1

為 `resume-explorer.ps1` 建立自動化測試，涵蓋 Snapshot 讀寫與驗證等可單元測試的邏輯；並評估在支援的 Windows 環境中加入端對端測試，驗證 Explorer 視窗與 Tabs 的還原行為。
