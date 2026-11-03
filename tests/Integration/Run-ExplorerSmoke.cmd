@echo off
setlocal
where /q pwsh.exe
if errorlevel 1 (
  echo PowerShell 7 pwsh.exe was not found. Install it in the test VM first.
  pause
  exit /b 3
)
pwsh.exe -NoProfile -Sta -File "%~dp0Start-ExplorerSmoke.ps1" -Run
set "smokeExit=%ERRORLEVEL%"
echo.
echo Explorer smoke exit code: %smokeExit%
echo 0=Passed, 1=Failed, 2=NotRun or pending review, 3=Blocked.
pause
exit /b %smokeExit%
