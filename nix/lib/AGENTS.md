# nix/lib: 共有ヘルパー

## 管理対象

- `default.nix`: `pkgs`, `lib`, `system` など共通値の公開

## 変更ルール

- ここは再利用前提の最小 API にする。
- ホスト専用の値は `nix/hosts/` に置く。
