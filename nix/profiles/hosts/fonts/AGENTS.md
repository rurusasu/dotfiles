# nix/profiles/hosts/fonts: フォント設定

## 管理対象

- `default.nix`: `fonts.packages` を定義

## ルール

- system-wide フォントのみ扱う。
- user-level フォント管理は別レイヤーに置く。
