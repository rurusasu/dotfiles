# nix/hosts/linux: Linux ホスト設定

## 管理対象

- `default.nix`
- `configuration.nix`

## ルール

- Linux 固有設定のみ置く。
- 共通設定は `nix/modules/host` に集約する。
