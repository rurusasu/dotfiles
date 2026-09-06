# nix/hosts/wsl: NixOS WSL ホスト設定

## 管理対象

- `default.nix`
- `configuration.nix`

`default.nix` が entrypoint であり、`configuration.nix` を import する。WSL 固有の option は
`configuration.nix` に置く。

## ルール

- WSL 固有設定のみ置く。
- 汎用化できる調整は `nix/modules/wsl` に寄せる。
