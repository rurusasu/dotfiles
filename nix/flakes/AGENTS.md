# nix/flakes: flake-parts 出力定義

## 管理対象

- `default.nix`: flake-parts エントリ
- `home.nix`: 非 NixOS 向け standalone home-manager 設定 wiring
- `hosts.nix`: `nixosConfigurations` wiring
- `lib/`: ヘルパー関数
- `packages.nix`: package outputs
- `systems.nix`: 対応プラットフォーム
- `treefmt.nix`: formatter wiring
- `tests.nix`: `tests/unit/` の nix-unit 登録と `tests/build/` の checks 登録

## 変更ルール

- 実装ロジックは `nix/hosts`, `nix/modules`, `nix/home` に寄せる。
- ここは出力配線を最小限に保つ。
- テスト本体や実行スクリプトは `nix/tests/` に置き、ここでは import する。
- nix-unit module が `checks.<system>.nix-unit` を生成する。ビルドテストを `nix-unit.tests` に混ぜない。
- package-provider-coverage は `packages.nix` の package-support-report と同じ derivation を公開し、treefmt の check は treefmt module が所有する。
