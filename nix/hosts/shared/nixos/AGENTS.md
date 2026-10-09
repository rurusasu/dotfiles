# nix/hosts/shared/nixos: native NixOS 共通設定

## 管理対象

- `default.nix`
- `configuration.nix`
- `platform.nix`: native NixOS と WSL 共通の OS option・Home Manager 配線
- Home Manager 設定は `../linux-home.nix` に置き、NixOS・standalone が共有する。
- `omarchy-keybindings.nix`: native NixOS の Hyprland セッション有効化と home 側 module の選択。ユーザー設定の実体は持たない

`default.nix` が entrypoint であり、`configuration.nix` を import する。ホスト固有の option は
`configuration.nix` に置く。

## ルール

- Linux 固有設定のみ置く。
- NixOS 共通の module 読み込みは `platform.nix`、OS 非依存のアプリ設定は `nix/modules/` に置く。
- 共通キー割り当ては `nix/home/keybindings/bindings.nix`、Lua 変換は `hyprland-renderer.nix`、Home Manager 設定は `hyprland.nix` に置く。native host からのみ module を読み込み、standalone でも使う `nix/hosts/shared/linux-home.nix` には無条件 import を追加しない。
- Hyprland/fuzzel の desktop package は native host が明示選択する。WSL/standalone の共通 package set へ追加しない。分割理由・対応範囲は [Omarchy 配列](../../../../docs/chezmoi/omarchy.md) を参照する。
