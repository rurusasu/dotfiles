# chezmoi

This source deploys the Windows WezTerm configuration at
`%USERPROFILE%/.config/wezterm/wezterm.lua` and installs the pinned UDEV Gothic
NF release for the current user. The font is registered under the current
Windows account, so no administrator privileges are needed.

Nix owns the font family defaults and WSLg fontconfig policy. Managed application
defaults use UDEV Gothic NF; Noto CJK and color emoji remain missing-glyph
fallbacks. NixOS-WSL places real UDEV regular/bold and fallback font files where
the WSLg server can read them. chezmoi deploys the canonical Nix XML to
`%USERPROFILE%/.config/dotfiles/wslg-fontconfig.conf` and configures
`%USERPROFILE%/.wslgconfig` to select it through its Windows-mounted path.
The XML reference therefore does not depend on a particular WSL distribution
starting first. Windows system UI fonts and website CSS are not forced.

Linux GUI GTK 3/4 and settings-portal fonts are configured by
`nix/modules/fonts/default.nix`; the NixOS host registers dconf for persistence.
Apply the Nix settings and Windows chezmoi settings before restarting WSLg to
load its new font environment and titlebar font cache. The 2026-10-14 verification
confirmed UDEV and Japanese text in the Chrome titlebar and Nautilus interface. See
[WSLg font setup](../docs/nix/nixos-wsl-install.md#wslg-のフォント)
for the ownership boundary and apply order.

The PowerShell 7 profile at
`%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` enables
PSReadLine's history prediction in `ListView`. Suggestions narrow as you type;
commands that have not been used remain available through ordinary Tab completion.
This setting works on Windows without WSL and is enabled when PSReadLine exposes
the `PredictionViewStyle` option in an interactive console.

Windows uses its standard desktop shortcuts. Unix GUI applications are installed
by Nix and opened from the WSL environment.

Setup output colors are managed here: `.chezmoi.toml.tmpl` enables chezmoi's
built-in diff colors (green additions and red removals), and `dot_taskrc.yml`
deploys `%USERPROFILE%/.taskrc.yml` to enable Task's command and diagnostic colors.
These settings also apply when setup forwards command output through PowerShell.
Use `chezmoi --color=false` or `task --color=false` for plain output, including
when saving logs. Application output keeps the colors provided by each tool;
plain messages such as `Setup Complete!` remain plain.

The key allocation is defined in `nix/home/keybindings/bindings.nix`,
`nix/modules/terminals/ghostty/ghostty.nix`, and `nix/modules/editors/nvim/neovim.nix`.
`task keybindings:export` directly evaluates those definitions with locked Nix
inputs and jq to update the committed `nix/home/keybindings/generated.json` export. chezmoi reads this export without
running Nix during apply. chezmoi also copies the exported Ghostty and Neovim data to
`~/.config/dotfiles/keybindings/` inside NixOS-WSL. Home Manager installs the
application loaders once; later key changes only require export and chezmoi.
WSLg Ghostty uses direct Ctrl+Alt+Shift resize shortcuts within the application.
Regenerate the export after editing the Nix allocation, then apply it with:

```powershell
task chezmoi
```

The normal `task install` flow installs Windows GUI apps, configures and applies
NixOS-WSL once to install the loaders, and applies Windows chezmoi to deploy the
exported data. `install.cmd` bootstraps the same Task entry when Task is not yet
installed. That flow consumes the committed JSON and does not regenerate it. On an
existing installation, run `nrs` once after adding this loader configuration,
then `task chezmoi`. Restart Neovim and reload Ghostty configuration after key
changes. GitHub Actions checks that the export matches Nix; it does not need to
generate or commit files on behalf of Windows installations.
