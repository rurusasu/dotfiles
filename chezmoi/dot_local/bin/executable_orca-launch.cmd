@echo off
setlocal
rem Launch Orca with 1Password-injected secrets so Codex child processes can
rem start GitHub MCP without a GITHUB_PAT_TOKEN warning.

set "ORCA_EXE=%LOCALAPPDATA%\Programs\orca\Orca.exe"
if not exist "%ORCA_EXE%" (
  echo Unable to locate Orca.exe at "%ORCA_EXE%" 1>&2
  exit /b 1
)

if "%SystemRoot%"=="" set "SystemRoot=C:\WINDOWS"
set "WHERE_EXE=%SystemRoot%\System32\where.exe"
set "OP_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\op.exe"
if not exist "%OP_EXE%" (
  for /f "delims=" %%I in ('"%WHERE_EXE%" op.exe 2^>nul') do (
    set "OP_EXE=%%I"
    goto :found_op
  )
)
:found_op

set "PERSONAL_ACCOUNT=EJLA3HRAVZBCXIQ7SRSFGQBTNU"
set "WORK_ACCOUNT=aimatecoltd.1password.com"
set "PERSONAL_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets.env"
set "WORK_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets-work.env"
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
  "%PWSH_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OP_RUN_GUI_LAUNCH%" -OpExe "%OP_EXE%" -PersonalAccount "%PERSONAL_ACCOUNT%" -PersonalEnvFile "%PERSONAL_SECRETS_ENV%" -WorkAccount "%WORK_ACCOUNT%" -WorkEnvFile "%WORK_SECRETS_ENV%" -TimeoutSeconds "%OP_RUN_TIMEOUT_SECONDS%" -Target "%ORCA_EXE%" %*
  exit /b %ERRORLEVEL%
)

start "" "%ORCA_EXE%" %*
