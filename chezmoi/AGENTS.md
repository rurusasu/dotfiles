# chezmoi: Windows user settings

- chezmoi deploys `%USERPROFILE%/.config/wezterm/wezterm.lua` on Windows and installs the pinned UDEV Gothic NF font for the current user.
- chezmoi also manages the PowerShell 7 profile in `%USERPROFILE%/Documents/PowerShell/` for WezTerm completion and PSReadLine history prediction.
- Windows Git's relative worktree links are configured in `dot_config/git/config`. Unix Git and gwq belong to Home Manager; use `task worktree:repair` for existing links.
- chezmoi applies the exported desktop shortcuts and conflict overrides to PowerToys Keyboard Manager through `scripts/powershell/Sync-PowerToysKeyboard.ps1`; Windows actions stay in `Invoke-DesktopAction.ps1`.
- Keep copy/cut/paste in the foreground-aware Windows action runtime so terminal copy does not become `Ctrl+C` / SIGINT in WSLg Ghostty. Windows clipboard history has its own first-use activation.
- Browser/URL actions and Spotify, Signal, Obsidian, and 1Password GUI launch in NixOS-WSL. Unix CLI and GUI installation declarations belong to `nix/modules/tools.nix`; the WSL host imports its `wslDesktop` selector, and application modules own their specific settings and package definitions. Windows PowerToys and existing 1Password CLI/signing integration remain host responsibilities. Do not reintroduce Windows app fallbacks for these WSL launchers.
- Keep desktop, Ghostty, and Neovim keys in `nix/home/keybindings/{bindings,ghostty,neovim}.nix` and refresh the committed `generated.json` with `task keybindings:export`. Do not duplicate key allocations in PowerShell or templates.
- Windows chezmoi deploys exported Ghostty and Neovim data into NixOS-WSL at `~/.config/dotfiles/keybindings/`. Home Manager owns the application loaders, plugins, and other Unix settings; native Unix reads the same Nix allocation directly.
- `install.cmd` runs `nrs` before chezmoi so new WSL loaders are installed before the exported data. Apply consumes the committed export without Nix; GHA verifies freshness rather than regenerating it.
- Run `task chezmoi` to apply the configuration.
