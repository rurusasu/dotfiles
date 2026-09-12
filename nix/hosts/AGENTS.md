# nix/hosts: ホスト別システム定義

## 構成

- `<host>/default.nix`: host の entrypoint。`configuration.nix` と共通 module を import する
- `<host>/configuration.nix`: system、service、user、cask、activation などのホスト固有設定

標準レイアウトは次のとおりです。

```text
nix/hosts/<host>/
├── default.nix
└── configuration.nix
```

Darwin も例外にせず、`nix/hosts/darwin/default.nix` を flake の entrypoint とし、実体は
`nix/hosts/darwin/configuration.nix` に置く。`default.nix` に system option を直接追加しない。

`hardware-configuration.nix` は全 host に必要な標準ファイルではない。native NixOS の実機では、
マシンごとの `/etc/nixos/hardware-configuration.nix` を `DOTFILES_NIXOS_HARDWARE_CONFIG` 経由で
読み込む。複数の実機で同じ host profile を使う場合も、hardware configuration は各マシン固有にする。
NixOS-WSL では通常不要で、Darwin では使用しない。

## ルール

- 共通化できる内容は `nix/modules/` へ移す。
