@echo off
setlocal
where /q pwsh.exe
if errorlevel 1 (
  echo PowerShell 7 pwsh.exe was not found. Install it and add it to PATH.
  set "offlineExit=2"
  goto finish
)
pwsh.exe -NoProfile -NonInteractive -File "%~dp0Invoke-Tests.ps1"
set "offlineExit=%ERRORLEVEL%"
:finish
echo.
echo Offline tests exit code: %offlineExit%
echo 0=Passed, 1=Suite failed, 2=Runner or evidence error. E2E is not run.
pause
exit /b %offlineExit%
