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

set "SECRETS_ENV=%USERPROFILE%\.config\shell\secrets.env"
if exist "%OP_EXE%" if exist "%SECRETS_ENV%" (
  "%OP_EXE%" run --env-file="%SECRETS_ENV%" -- cmd /d /c start "" "%ORCA_EXE%" %*
  exit /b %ERRORLEVEL%
)

start "" "%ORCA_EXE%" %*
