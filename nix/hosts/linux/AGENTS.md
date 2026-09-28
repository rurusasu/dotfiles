# nix/hosts/linux: Linux ホスト設定

## 管理対象

- `default.nix`
- `configuration.nix`
- `omarchy-keybindings.nix`: native NixOS の Hyprland セッション有効化と home 側 module の選択。ユーザー設定の実体は持たない

`default.nix` が entrypoint であり、`configuration.nix` を import する。ホスト固有の option は
`configuration.nix` に置く。

## ルール

- Linux 固有設定のみ置く。
- 共通設定は `nix/modules/host` に集約する。
- 共通キー割り当ては `nix/home/keybindings/bindings.nix`、Lua 変換は `hyprland-renderer.nix`、Home Manager 設定は `hyprland.nix` に置く。native host からのみ module を読み込み、standalone でも使う `nix/home/linux.nix` には無条件 import を追加しない。
- Hyprland/fuzzel の desktop package は native host が明示選択する。WSL/standalone の共通 package set へ追加しない。分割理由・対応範囲は [Omarchy 配列](../../../docs/chezmoi/omarchy.md) を参照する。
