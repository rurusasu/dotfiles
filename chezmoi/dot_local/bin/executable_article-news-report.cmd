@echo off
setlocal
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.local\bin\article-news-report.ps1" %*
exit /b %ERRORLEVEL%
