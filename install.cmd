@echo off
setlocal
"%SystemRoot%\System32\chcp.com" 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul

if defined DOTFILES_PS7_DIR (
  set "PS7_DIR=%DOTFILES_PS7_DIR%"
) else (
  set "PS7_DIR=%ProgramFiles%\PowerShell\7"
)
if exist "%PS7_DIR%\pwsh.exe" (
  set "PATH=%PS7_DIR%;%PATH%"
  set "PS_CMD=%PS7_DIR%\pwsh.exe"
)

if not defined PS_CMD if exist "%SystemRoot%\System32\where.exe" (
  "%SystemRoot%\System32\where.exe" pwsh >nul 2>&1
  if not errorlevel 1 (
    set "PS_CMD=pwsh"
  )
)

if not defined PS_CMD (
  echo [INFO] pwsh not found. Falling back to Windows PowerShell.
  if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    set "PS_CMD=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
  ) else (
    set "PS_CMD=powershell.exe"
  )
)

"%PS_CMD%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\powershell\install.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

popd >nul
exit /b %EXIT_CODE%
