# Ghostty (macOS / Linux)

Ghostty is installed alongside WezTerm; neither the default terminal nor existing
WezTerm settings are changed. Package selection lives in `nix/packages/sets.nix`:
macOS uses `ghostty-bin` (the signed application bundle), Linux uses `ghostty`.
The macOS GUI belongs to the nix-darwin system package set, not Home Manager.

Apply packages using the repository's normal `./install.sh` workflow. Apply the
shared terminal configuration with `task chezmoi`. It deploys `config` to
`${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config` on macOS/Linux only.
The configuration uses Catppuccin Mocha, UDEV Gothic NF at size 10, and retains
Ghostty's native shortcuts and automatic shell integration. The font is already
managed by the package catalog. Windows deployment is unchanged.

Launch Ghostty.app on macOS, or `ghostty` in a graphical Linux session. A headless
Linux session cannot display the application; WSL requires WSLg or another display
server. Non-NixOS Linux installations also need a compatible graphics-driver setup
(for example, Home Manager's nixGL integration); installing the Nix package alone
does not supply the host GPU drivers. See the
[official Nix installation notes](https://ghostty.org/docs/install/binary#nix).

On macOS, an existing `~/Library/Application Support/com.mitchellh.ghostty/config`
can override the shared XDG config. Review any existing settings there if the
appearance differs. This setup does not remove that file.

Validate with `ghostty +validate-config`, and inspect available fonts with
`ghostty +list-fonts`. Use `task test:nix` for package-selection tests and
`nix build .#checks.aarch64-darwin.ghostty-config --no-link` (or the Linux system
name) for the isolated deployment check.
