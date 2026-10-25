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

PowerToys Keyboard Manager applies the Omarchy desktop shortcuts with
`Super=Win`: application launchers, clipboard, capture, notifications, appearance,
idle, night light, taskbar, and audio output actions. `Win+Enter` opens Ghostty
in the `NixOS` WSL distribution; Btop, Neovim, and LazyDocker also open there.
The browser, Nautilus (Files), and Spotify, Signal, Obsidian, and 1Password GUI
launch in WSLg from Nix-managed packages. `Win+Shift+F` opens Nautilus.
HEY, ChatGPT, Google Messages, and WhatsApp open in WSL Chrome app windows.
PowerToys remains a Windows host dependency. The Windows 1Password installation
remains for existing CLI/signing integration; the GUI shortcut opens the WSL
application. Existing Windows applications are not automatically uninstalled.
See the
[Windows action details](../docs/chezmoi/omarchy.md#windows-デスクトップの運用)
for platform equivalents and requirements.

The key allocation is defined in `nix/home/keybindings/bindings.nix`,
`ghostty.nix`, and `neovim.nix`.
`task keybindings:export` builds `.#keybindings-json` and updates the committed
`nix/home/keybindings/generated.json` export. chezmoi reads this export without
running Nix during apply. `scripts/powershell/Sync-PowerToysKeyboard.ps1` owns
PowerToys serialization; `Invoke-DesktopAction.ps1` implements Windows actions.
Copy, cut, and paste go through this runtime so Windows applications receive
their usual shortcuts and WSLg Ghostty receives terminal copy/paste shortcuts.
`Win+X` copies selected Ghostty output because terminal output cannot be cut.
An unidentified foreground WSLg application produces an error instead of
receiving a possible `Ctrl+C` / SIGINT.
chezmoi also copies the exported Ghostty and Neovim data to
`~/.config/dotfiles/keybindings/` inside NixOS-WSL. Home Manager installs the
application loaders once; later key changes only require export and chezmoi.
Ghostty's Win resize chords use a generated transport mapping scoped to
`msrdc.exe` (all WSLg windows); native Windows applications are unaffected.

The deployment merges into the active PowerToys keyboard profile and preserves
unrelated settings and mappings. It enables Keyboard Manager and Color Picker,
restarting a running PowerToys when activation requires it; subsequent mapping
changes reload the keyboard engine. Desired remaps override their Windows
shortcuts and `Win+D` is disabled. OS-reserved `Win+L` and `Ctrl+Alt+Del` remain
Windows operations. Regenerate the export after editing the Nix key allocation;
Nix unit checks reject a stale export. Apply the committed export or adapter with:

```powershell
task chezmoi
```

The normal `install.cmd` flow installs Windows GUI apps, configures NixOS-WSL,
then runs `nrs` to install the loaders and Windows chezmoi to deploy the exported
data. That flow consumes the committed JSON and does not regenerate it. On an
existing installation, run `nrs` once after adding this loader configuration,
then `task chezmoi`. Restart Neovim and reload Ghostty configuration after key
changes. GitHub Actions checks that the export matches Nix; it does not need to
generate or commit files on behalf of Windows installations.

Notification, night light, and audio actions use Windows 11 UI Automation with
English and Japanese control labels, so Windows UI changes can affect them.
Action failures display an error and append details to
`%LOCALAPPDATA%/dotfiles/keybindings/actions.log`.

If clipboard history is disabled, press `Win+Ctrl+V` and select **Turn on**
(`有効にする`) once. This is the Windows first-use step described by
[Microsoft](https://support.microsoft.com/ja-jp/windows/apps/using-the-clipboard).
Manage the unmodified `PrintScreen` binding through the Nix export: the current
PowerToys editor can lose it when toggled off and on in the GUI.

Actual key observations and actions still awaiting verification are recorded in
[the verification report](../docs/chezmoi/keybindings-verification.md).
