# nix/hosts: ホスト別システム定義

## 構成

- `<host>/default.nix`: imports と統合
- `<host>/configuration.nix`: ホスト固有設定
- `<host>/hardware-configuration.nix`: NixOS ハードウェア設定

## ルール

- 共通化できる内容は `nix/modules/` へ移す。
