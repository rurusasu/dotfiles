# nix/flakes: flake-parts 出力定義

## 管理対象

- `default.nix`: flake-parts エントリ
- `hosts.nix`: `nixosConfigurations` wiring
- `packages.nix`: package outputs
- `systems.nix`: 対応プラットフォーム
- `templates.nix`: flake templates
- `treefmt.nix`: formatter wiring

## 変更ルール

- 実装ロジックは `nix/hosts`, `nix/modules`, `nix/profiles` に寄せる。
- ここは出力配線を最小限に保つ。
