# chezmoi

This source merges Windows Terminal defaults into its stable `settings.json`,
generates its theme and font settings from `nix/home/appearance.json`, and installs the pinned UDEV Gothic
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

Windows uses its standard desktop shortcuts outside marked WSL terminal controls.
The user-level `WslSuperKey` adapter forwards Win chords from those controls as Super
input. It is compiled from `scripts/powershell/WslSuperKey.cs` by chezmoi, starts at
login through HKCU Run, and uses neither PowerToys nor administrator privileges.
Unix GUI applications are installed by Nix and opened from the WSL environment.

Setup output colors are managed here: `.chezmoi.toml.tmpl` enables chezmoi's
built-in diff colors (green additions and red removals), and `dot_taskrc.yml`
deploys `%USERPROFILE%/.taskrc.yml` to enable Task's command and diagnostic colors.
These settings also apply when setup forwards command output through PowerShell.
Use `chezmoi --color=false` or `task --color=false` for plain output, including
when saving logs. Application output keeps the colors provided by each tool;
plain messages such as `Setup Complete!` remain plain.

The shared key allocation is defined in `nix/home/keybindings/bindings.nix`
and `nix/modules/editors/nvim/default.nix`.
Home Manager generates Neovim settings from those definitions on every Unix
platform, including NixOS-WSL. Apply key changes with `nrs` and restart Neovim.
`task keybindings:export` exports only `nix/home/appearance.json`, using the common
Catppuccin flavor and font settings. chezmoi reads this appearance export without
running Nix during apply and does not deploy key data into WSL.
Home Manager owns Ghostty and Herdr settings on every Unix platform. Ghostty
provides the host terminal; Herdr owns terminal tabs, panes, and sessions through
its `Ctrl+Space` prefix. Ghostty has no split or tab keybindings.

Regenerate the appearance export after editing the common theme or font, then apply it with:

```powershell
task keybindings:export
task chezmoi
```

The normal `task install` flow installs Windows GUI apps, configures and applies
NixOS-WSL once to apply its application settings, and applies Windows chezmoi.
`install.cmd` bootstraps the same Task entry when Task is not yet
installed. That flow consumes the committed JSON and does not regenerate it. On an
existing installation, run `nrs` once after adding this loader configuration,
then `task chezmoi`. Restart Neovim after shared key changes. Apply Ghostty and
Herdr changes with `nrs`. GitHub Actions checks that the export matches Nix; it does not need to
generate or commit files on behalf of Windows installations.
