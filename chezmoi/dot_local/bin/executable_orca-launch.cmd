@echo off
setlocal
rem Launch Orca without eager 1Password prompts by default.
rem Set DOTFILES_GUI_EAGER_SECRET_LOAD=1 to opt in to the bounded op run path
rem when Codex MCP startup secrets must be present before shell profiles run.

if "%SystemRoot%"=="" set "SystemRoot=C:\WINDOWS"
if "%WINDIR%"=="" set "WINDIR=%SystemRoot%"
if "%ComSpec%"=="" set "ComSpec=%SystemRoot%\System32\cmd.exe"
if "%USERPROFILE%"=="" set "USERPROFILE=%HOMEDRIVE%%HOMEPATH%"
if "%HOME%"=="" set "HOME=%USERPROFILE%"
if "%LOCALAPPDATA%"=="" set "LOCALAPPDATA=%USERPROFILE%\AppData\Local"
if "%APPDATA%"=="" set "APPDATA=%USERPROFILE%\AppData\Roaming"
if "%TEMP%"=="" set "TEMP=%LOCALAPPDATA%\Temp"
if "%TMP%"=="" set "TMP=%TEMP%"
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0;%USERPROFILE%\.local\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
set "DOTFILES_ORCA_LAUNCH=1"

set "ORCA_EXE=%LOCALAPPDATA%\Programs\orca\Orca.exe"
if not exist "%ORCA_EXE%" (
  echo Unable to locate Orca.exe at "%ORCA_EXE%" 1>&2
  exit /b 1
)

set "CODEX_LOGIN_PREFLIGHT=%USERPROFILE%\.local\bin\stop-stale-codex-login.ps1"
set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\pwsh.exe"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%PWSH_EXE%" set "POWERSHELL_EXE=%PWSH_EXE%"
set "CODEX_LOGIN_STALE_AFTER_SECONDS=%DOTFILES_CODEX_LOGIN_STALE_AFTER_SECONDS%"
if "%CODEX_LOGIN_STALE_AFTER_SECONDS%"=="" set "CODEX_LOGIN_STALE_AFTER_SECONDS=120"
if exist "%CODEX_LOGIN_PREFLIGHT%" if exist "%POWERSHELL_EXE%" (
  "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CODEX_LOGIN_PREFLIGHT%" -AdoptRuntimeCodexAuth -StaleAfterSeconds "%CODEX_LOGIN_STALE_AFTER_SECONDS%"
)

if "%DOTFILES_GUI_EAGER_SECRET_LOAD%"=="1" goto :eager_secret_launch
goto :launch_orca

:eager_secret_launch
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

:launch_orca
start "" "%ORCA_EXE%" %*
