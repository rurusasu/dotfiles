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
op run --env-file="%USERPROFILE%\.config\shell\secrets.env" -- wezterm
