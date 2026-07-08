@echo off
rem Launch WezTerm with 1Password-injected secrets (op run official pattern).
rem
rem  - One biometric prompt on WezTerm startup; no further prompts per tab.
rem  - WSLENV bridges GITHUB_PAT_TOKEN / TAVILY_API_KEY / GITHUB_WORK_TOKEN into WSL child processes
rem    so env.sh guard triggers and op.exe inject is skipped there too.
rem
rem Usage: pin this file to taskbar or create a Start-menu shortcut.
rem        Replace any existing "WezTerm" shortcut with this launcher.

set WSLENV=GITHUB_PAT_TOKEN:TAVILY_API_KEY:GITHUB_WORK_TOKEN
if "%SystemRoot%"=="" set "SystemRoot=C:\WINDOWS"
set "WHERE_EXE=%SystemRoot%\System32\where.exe"
set "PERSONAL_ACCOUNT=EJLA3HRAVZBCXIQ7SRSFGQBTNU"
set "WORK_ACCOUNT=aimatecoltd.1password.com"
set "PERSONAL_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets.env"
set "WORK_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets-work.env"
set "OP_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\op.exe"
if not exist "%OP_EXE%" set "OP_EXE=op"
set "OP_RUN_GUI_LAUNCH=%USERPROFILE%\.local\bin\op-run-gui-launch.ps1"
set "OP_RUN_TIMEOUT_SECONDS=%DOTFILES_OP_RUN_TIMEOUT_SECONDS%"
if "%OP_RUN_TIMEOUT_SECONDS%"=="" set "OP_RUN_TIMEOUT_SECONDS=8"
set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\pwsh.exe"
if not exist "%PWSH_EXE%" (
  for /f "delims=" %%I in ('"%WHERE_EXE%" pwsh.exe 2^>nul') do (
    set "PWSH_EXE=%%I"
    goto :found_pwsh
  )
)
:found_pwsh

if exist "%OP_EXE%" if exist "%PERSONAL_SECRETS_ENV%" if exist "%OP_RUN_GUI_LAUNCH%" if exist "%PWSH_EXE%" (
  "%PWSH_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OP_RUN_GUI_LAUNCH%" -OpExe "%OP_EXE%" -PersonalAccount "%PERSONAL_ACCOUNT%" -PersonalEnvFile "%PERSONAL_SECRETS_ENV%" -WorkAccount "%WORK_ACCOUNT%" -WorkEnvFile "%WORK_SECRETS_ENV%" -TimeoutSeconds "%OP_RUN_TIMEOUT_SECONDS%" -Target "wezterm" %*
  exit /b %ERRORLEVEL%
)

wezterm
