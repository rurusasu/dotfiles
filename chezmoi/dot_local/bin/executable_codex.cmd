@echo off
setlocal
rem Launch Codex CLI with 1Password-injected secrets so plugin MCP servers can
rem read GITHUB_PAT_TOKEN during Codex startup.

set "TERM=xterm-256color"
set "CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT=1"
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

set "CODEX_EXE="
for /d %%I in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\OpenAI.Codex_*") do (
  if not defined CODEX_EXE if exist "%%~fI\codex-x86_64-pc-windows-msvc.exe" set "CODEX_EXE=%%~fI\codex-x86_64-pc-windows-msvc.exe"
  if not defined CODEX_EXE if exist "%%~fI\codex.exe" set "CODEX_EXE=%%~fI\codex.exe"
)
if not defined CODEX_EXE set "CODEX_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\codex.exe"
if not exist "%CODEX_EXE%" (
  for /f "delims=" %%I in ('"%WHERE_EXE%" codex.exe 2^>nul') do (
    set "CODEX_EXE=%%I"
    goto :found_codex
  )
)

:found_codex
if not exist "%CODEX_EXE%" (
  echo Unable to locate codex.exe 1>&2
  exit /b 1
)

if /i "%~1"=="login" goto :login_codex

set "PERSONAL_ACCOUNT=EJLA3HRAVZBCXIQ7SRSFGQBTNU"
set "WORK_ACCOUNT=aimatecoltd.1password.com"
set "PERSONAL_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets.env"
set "WORK_SECRETS_ENV=%USERPROFILE%\.config\shell\secrets-work.env"

set "NEEDS_SECRET_LOAD="
if "%GITHUB_PAT_TOKEN%"=="" set "NEEDS_SECRET_LOAD=1"
if "%GITHUB_WORK_TOKEN%"=="" set "NEEDS_SECRET_LOAD=1"

if defined NEEDS_SECRET_LOAD if exist "%OP_EXE%" (
  if exist "%PERSONAL_SECRETS_ENV%" if exist "%WORK_SECRETS_ENV%" (
    "%OP_EXE%" run --account "%PERSONAL_ACCOUNT%" --env-file="%PERSONAL_SECRETS_ENV%" -- "%OP_EXE%" run --account "%WORK_ACCOUNT%" --env-file="%WORK_SECRETS_ENV%" -- "%CODEX_EXE%" %*
    exit /b %ERRORLEVEL%
  )

  if exist "%PERSONAL_SECRETS_ENV%" (
    "%OP_EXE%" run --account "%PERSONAL_ACCOUNT%" --env-file="%PERSONAL_SECRETS_ENV%" -- "%CODEX_EXE%" %*
    exit /b %ERRORLEVEL%
  )

  if exist "%WORK_SECRETS_ENV%" (
    "%OP_EXE%" run --account "%WORK_ACCOUNT%" --env-file="%WORK_SECRETS_ENV%" -- "%CODEX_EXE%" %*
    exit /b %ERRORLEVEL%
  )
)

:login_codex
set "CODEX_LOGIN_PREFLIGHT=%~dp0stop-stale-codex-login.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if "%DOTFILES_ORCA_LAUNCH%"=="1" if not "%CODEX_HOME%"=="" (
  if exist "%CODEX_LOGIN_PREFLIGHT%" if exist "%POWERSHELL_EXE%" (
    "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CODEX_LOGIN_PREFLIGHT%" -InitializeManagedCodexHomeFromRuntimeAuth
    if not errorlevel 1 exit /b 0
  )
)
if exist "%CODEX_LOGIN_PREFLIGHT%" if exist "%POWERSHELL_EXE%" (
  "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CODEX_LOGIN_PREFLIGHT%"
)

:launch_codex
"%CODEX_EXE%" %*
exit /b %ERRORLEVEL%
