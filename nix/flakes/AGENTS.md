# nix/flakes: flake-parts 出力定義

## 管理対象

- `default.nix`: flake-parts エントリ
- `home.nix`: 非 NixOS 向け standalone home-manager 設定 wiring
- `hosts.nix`: `nixosConfigurations` wiring
- `lib/`: ヘルパー関数
- `packages.nix`: package outputs
- `systems.nix`: 対応プラットフォーム
- `treefmt.nix`: formatter wiring

## 変更ルール

- 実装ロジックは `nix/hosts`, `nix/modules`, `nix/home` に寄せる。
- ここは出力配線を最小限に保つ。
