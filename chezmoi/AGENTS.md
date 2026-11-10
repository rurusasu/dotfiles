# chezmoi: Windows user settings

- chezmoi merges the managed defaults into Windows Terminal's stable `settings.json`, installs its color-scheme fragment and the pinned UDEV Gothic NF font, and selects Windows Terminal as the current user's default terminal.
- Keep existing Windows Terminal profiles and keybindings. Use the standard PowerShell 7 profile as default and let WSL generate its distribution profiles.
- chezmoi also manages the PowerShell 7 profile in `%USERPROFILE%/Documents/PowerShell/` for PSReadLine history prediction.
- The same profile owns Windows-native shell aliases and functions for applications declared in the WinGet manifest (`eza`, `ls`/`ll`/`la`/`lt`/`lla`, `grep`, `find`, `lg`). Keep these in chezmoi; do not route them through WSL. CLI install metadata remains in `chezmoi/winget/packages.json`.
- Superfile's Windows configuration is managed in `AppData/Local/superfile/config.toml`; its hotkeys, pins, and runtime state remain application-managed.
- Setup output colors belong to `.chezmoi.toml.tmpl` (chezmoi diffs) and `dot_taskrc.yml` (Task's own output). Prefer native tool configuration over ANSI coloring in installer scripts.
- Windows Git's relative worktree links are configured in `dot_config/git/config`. Unix Git and gwq belong to Home Manager; use `task worktree:repair` for existing links.
- Windows keeps its standard desktop shortcuts outside Windows Terminal's marked WSL terminal controls. The per-user `WslSuperKey` adapter consumes Win chords there and forwards Super-modified terminal input. Do not add a Windows desktop action runtime or PowerToys dependency.
- Unix GUI applications belong to NixOS-WSL and Home Manager. Each application module in `nix/modules/` owns its package selection, settings, integrations, and dedicated runtime dependencies. Enablement, simple package lists, and single assignments belong directly in the required `nix/home/` composition. Common and OS-specific composition explicitly imports the relevant modules outside that directory. OS-specific settings, privileged operations, system services, and integration belong to `nix/hosts/`. Existing Windows 1Password CLI/signing integration remains a host responsibility.
- Keep desktop keys in `nix/home/keybindings/bindings.nix` and Neovim keys in `nix/modules/editors/nvim/default.nix`. Home Manager generates their application settings directly on every Unix platform, including NixOS-WSL. Do not duplicate key allocations in PowerShell or templates.
- Home Manager owns Neovim keys, plugins, Ghostty, Herdr, and other Unix settings. Windows chezmoi does not deploy key data into WSL. Apply changes to WSL application keys through `./install.sh`.
- `task install` updates and switches NixOS once in its WSL phase before applying Windows chezmoi. `install.cmd` bootstraps that same Task entry. `task keybindings:export` exports only the common appearance to `chezmoi/appearance/appearance.json`; chezmoi consumes it without Nix, and GHA verifies freshness rather than regenerating it.
- Run `task chezmoi` to apply the configuration.

- WSL ホストの設定は `dot_wslconfig` が所有し、chezmoi が `%USERPROFILE%/.wslconfig` へ配布する。反映後に WSL を停止・再起動して読み直す。
