# nix/flakes/lib: flake 補助関数

## 管理対象

- `hosts.nix`: `mkNixos` などの構築ヘルパー
- `shared-modules.nix`: 共有モジュール定義

## 変更ルール

- 依存方向は `lib -> hosts/modules/profiles` に限定する。
- ホスト固有条件をこの層へ持ち込まない。
