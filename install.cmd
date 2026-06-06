@echo off
setlocal
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul

set "PS7_DIR=%ProgramFiles%\PowerShell\7"
if exist "%PS7_DIR%\pwsh.exe" (
  set "PATH=%PS7_DIR%;%PATH%"
)

set "PS_CMD=pwsh"
where pwsh >nul 2>&1
if errorlevel 1 (
  set "PS_CMD=powershell.exe"
  echo [INFO] pwsh not found. Falling back to Windows PowerShell.
)

"%PS_CMD%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\powershell\install.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

popd >nul
exit /b %EXIT_CODE%
