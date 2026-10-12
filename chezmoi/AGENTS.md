# chezmoi: Windows user settings

- chezmoi deploys `%USERPROFILE%/.config/wezterm/wezterm.lua` on Windows and installs the pinned UDEV Gothic NF font for the current user.
- chezmoi also manages the PowerShell 7 profile in `%USERPROFILE%/Documents/PowerShell/` for WezTerm completion and PSReadLine history prediction.
- Home Manager owns WezTerm and user settings on macOS, Linux, and WSL.
- Run `task chezmoi` to apply the configuration.
