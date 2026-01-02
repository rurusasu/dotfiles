# AGENTS

Purpose
- Windows-side installer helpers and execution guidance.

Wrapper
- Reason: Windows built-in `sudo` may try to execute `.ps1` as a Win32 app and fail (`0x800700C1`).
- Fix: use the CMD wrapper to invoke PowerShell explicitly.

Recommended usage for AI agents
- Prefer `sudo .\install-nixos-wsl.cmd` to ensure elevated execution works without interactive prompts.
- Alternatively, run an elevated PowerShell and execute `.\install-nixos-wsl.ps1` directly.
