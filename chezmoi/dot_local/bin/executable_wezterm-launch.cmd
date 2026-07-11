@echo off
rem Launch WezTerm without eager 1Password prompts by default.
rem
rem  - WSLENV bridges existing GITHUB_PAT_TOKEN / TAVILY_API_KEY / GITHUB_WORK_TOKEN
rem    into WSL child processes when they are already present.
rem  - Set DOTFILES_GUI_EAGER_SECRET_LOAD=1 to opt in to the old bounded
rem    op run path for apps that must receive secrets before shell profiles run.
rem
rem Usage: pin this file to taskbar or create a Start-menu shortcut.
rem        Replace any existing "WezTerm" shortcut with this launcher.

if "%SystemRoot%"=="" set "SystemRoot=C:\WINDOWS"
set "WHERE_EXE=%SystemRoot%\System32\where.exe"
set "WEZTERM_EXE=%ProgramFiles%\WezTerm\wezterm-gui.exe"
if exist "%WEZTERM_EXE%" goto :found_wezterm
set "WEZTERM_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\wezterm-gui.exe"
if exist "%WEZTERM_EXE%" goto :found_wezterm
set "WEZTERM_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\wezterm.exe"
if exist "%WEZTERM_EXE%" goto :found_wezterm
for /f "delims=" %%I in ('"%WHERE_EXE%" wezterm-gui.exe 2^>nul') do (
  set "WEZTERM_EXE=%%I"
  goto :found_wezterm
)
for /f "delims=" %%I in ('"%WHERE_EXE%" wezterm.exe 2^>nul') do (
  set "WEZTERM_EXE=%%I"
  goto :found_wezterm
)
set "WEZTERM_EXE=wezterm"
:found_wezterm

set WSLENV=GITHUB_PAT_TOKEN:TAVILY_API_KEY:GITHUB_WORK_TOKEN
if "%DOTFILES_GUI_EAGER_SECRET_LOAD%"=="1" goto :eager_secret_launch
goto :launch_wezterm

:eager_secret_launch
set "PERSONAL_ACCOUNT=EJLA3HRAVZBCXIQ7SRSFGQBTNU"
set "WORK_ACCOUNT=aimatecoltd.1password.com"
set "PERSONAL_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets.env"
set "WORK_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets-work.env"
set "OP_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\op.exe"
if not exist "%OP_EXE%" (
  for /f "delims=" %%I in ('"%WHERE_EXE%" op.exe 2^>nul') do (
    set "OP_EXE=%%I"
    goto :found_op
  )
)
:found_op
set "OP_RUN_GUI_LAUNCH=%USERPROFILE%\.local\bin\op-run-gui-launch.ps1"
set "OP_RUN_TIMEOUT_SECONDS=%DOTFILES_OP_RUN_TIMEOUT_SECONDS%"
if "%OP_RUN_TIMEOUT_SECONDS%"=="" set "OP_RUN_TIMEOUT_SECONDS=60"
set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\pwsh.exe"
if not exist "%PWSH_EXE%" (
  for /f "delims=" %%I in ('"%WHERE_EXE%" pwsh.exe 2^>nul') do (
    set "PWSH_EXE=%%I"
    goto :found_pwsh
  )
)
:found_pwsh

if exist "%OP_EXE%" if exist "%PERSONAL_SECRETS_ENV%" if exist "%OP_RUN_GUI_LAUNCH%" if exist "%PWSH_EXE%" (
  "%PWSH_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OP_RUN_GUI_LAUNCH%" -OpExe "%OP_EXE%" -PersonalAccount "%PERSONAL_ACCOUNT%" -PersonalEnvFile "%PERSONAL_SECRETS_ENV%" -WorkAccount "%WORK_ACCOUNT%" -WorkEnvFile "%WORK_SECRETS_ENV%" -TimeoutSeconds "%OP_RUN_TIMEOUT_SECONDS%" -Target "%WEZTERM_EXE%" %*
  exit /b %ERRORLEVEL%
)

:launch_wezterm
if "%WEZTERM_EXE%"=="wezterm" (
  wezterm %*
  exit /b %ERRORLEVEL%
)
start "" "%WEZTERM_EXE%" %*
