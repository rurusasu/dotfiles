@echo off
setlocal
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul

set "PS_CMD=pwsh"
where pwsh >nul 2>&1
if errorlevel 1 (
  set "PS_CMD=powershell.exe"
  echo [INFO] pwsh not found. Falling back to Windows PowerShell.
)

:: Ensure UTF-8 BOM on all .ps1 files so PowerShell 5.1 parses Japanese strings correctly
"%PS_CMD%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$bom=[byte[]](0xEF,0xBB,0xBF);Get-ChildItem '%SCRIPT_DIR%scripts\powershell' -Recurse -Filter '*.ps1'|ForEach-Object{$b=[System.IO.File]::ReadAllBytes($_.FullName);if(-not($b.Length-ge 3-and$b[0]-eq 0xEF-and$b[1]-eq 0xBB-and$b[2]-eq 0xBF)){[System.IO.File]::WriteAllBytes($_.FullName,$bom+$b)}};$entry='%SCRIPT_DIR%scripts\powershell\install.ps1';$b=[System.IO.File]::ReadAllBytes($entry);if(-not($b[0]-eq 0xEF)){[System.IO.File]::WriteAllBytes($entry,$bom+$b)}"

"%PS_CMD%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\powershell\install.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

popd >nul
exit /b %EXIT_CODE%
