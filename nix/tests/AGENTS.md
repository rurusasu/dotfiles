# nix/tests: テストの配置と登録

## 責務

- `unit/`: nix-unit が評価する `expr` / `expected` の属性セット。
- `build/`: ビルド、生成物比較、外部プロセス実行を検証する derivation。
- `fixtures/`: 共有する pkgs 構築関数や VM 用 module。テストとして登録しない。
- 詳細な実行手順と Bats の責務分類は [README.md](README.md) を参照する。

## 変更時

- テストの戻り値と検証対象で配置を決める。unit と build はどちらも flake の `checks` 経由で実行する。
- テスト本体はここに置き、`nix/tests/default.nix` に一度だけ登録する。
- 移動時は相対 import、README、CI routing、Bats / PowerShell の固定パスを同時に更新する。
- unit の登録漏れ・重複と build の登録漏れ・重複は `unit/ownership.nix` が検査する。
- 既存の公開 check 名と OS 制約を維持する。VM テストは Linux builder が必要。
- fixture に実際の認証情報や個人データを入れず、実機の設定として適用しない。

## 検証

- 全 system の評価: `nix flake check --all-systems --no-build --no-write-lock-file`。
- 単体テスト: `nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file`。
- ビルドテスト: 対象の `checks.<system>.<name>` を build する。Unix の通常セットは `task test:nix`。
- `--no-build` の成功をテスト成功として報告しない。実機・VM 未実行の範囲を明示する。
