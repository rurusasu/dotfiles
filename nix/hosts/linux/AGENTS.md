# nix/hosts/linux: Linux ホスト設定

## 管理対象

- `default.nix`
- `configuration.nix`

`default.nix` が entrypoint であり、`configuration.nix` を import する。ホスト固有の option は
`configuration.nix` に置く。

## ルール

- Linux 固有設定のみ置く。
- 共通設定は `nix/modules/host` に集約する。
