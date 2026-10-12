# chezmoi

This source deploys the Windows WezTerm configuration at
`%USERPROFILE%/.config/wezterm/wezterm.lua` and installs the pinned UDEV Gothic
NF release for the current user. The font is registered under the current
Windows account, so no administrator privileges are needed.

```powershell
task chezmoi
```
