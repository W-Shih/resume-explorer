# Issue-3 — Restore 滑鼠焦點獨立性驗證計畫

日期：2026-11-01；狀態：待實作／待驗證；**本次僅拆分文件，不改 Restore 程式碼**。

來源案例：`02e5f26b61da4a1ba503bea37d15323f.json`。真實 Report 含使用者路徑，不得提交公開 repo。

對應：`Backlog.md` Issue-3（P2）。本計畫只處理焦點／使用者互動；背景不搶焦點是獨立的 Feature Request-1。

## 問題背景

目前沒有證據證明單純點擊其他應用會造成超時。同步觀測延遲另見 `resume-explorer-Issue-4-synchronous-timeout-plan.md`。

## Restore 不應受無關滑鼠焦點影響

**產品不變量**：單純將 Chrome／Visual Studio／其他應用帶到前景，不應使正在還原的 Tab 被導覽到錯誤路徑、錯認 identity、或因焦點切換本身而失敗。既有設計使用 UIA InvokePattern、Shell COM Navigate2 與身份觀測，並不依賴 SendKeys 或滑鼠座標；此為預期設計，**尚未通過完整實機回歸驗收**。

區分：(A) 只變更其他應用前景；(B) 切換另一個 Explorer 視窗；(C) 在同個目標 Explorer 切換 active Tab；(D) 手動在目標視窗新增／關閉 Tab；(E) 關閉目標視窗。A/B 應盡量不影響；C 需驗證；D/E 改變共享狀態，若造成 candidate ambiguity／window loss，應停止且不猜選。這與 Feature Request-1 的「Restore 自身不搶焦點、不彈視窗」不同。

**驗證**：建立可控的多視窗測試矩陣，在相同 Snapshot、Tab 數量、VDI 負載及 timeout 下，對照無互動與 A–E；記錄 elapsed、candidate identity、path 及原因碼。測試不得藉由放寬驗證來製造假成功；不得誤導到其他現有分頁。若 A/B 可靠重現失敗，再追查 UIA Invoke 或 COM 的 active-tab 相依性。

## 相關工作與共通保護

- 保留 Issue-2 的單次 Invoke／Navigate、Tab identity、原子 checkpoint、OutcomeUnknown 與 PreviewRetry／Retry 安全規則。
- 在隔離 Windows 測試環境執行 E2E，不直接於使用中的 Explorer 壓測；完成後更新 Backlog、README 與驗證紀錄。

- 性能量測與同步阻塞的修復由 Issue-4 負責；報告體積由 Feature Request-6 負責。
