# chezmoi

This source deploys the Windows WezTerm configuration at
`%USERPROFILE%/.config/wezterm/wezterm.lua` and installs the pinned UDEV Gothic
NF release for the current user. The font is registered under the current
Windows account, so no administrator privileges are needed.

The PowerShell 7 profile at
`%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` enables
PSReadLine's history prediction in `ListView`. Suggestions narrow as you type;
commands that have not been used remain available through ordinary Tab completion.
This setting works on Windows without WSL and requires PSReadLine 2.2.2 or later.

```powershell
task chezmoi
```
