# build: ビルド・実行テスト

- 各ファイルは derivation を返す。`expr` / `expected` の単体テストは `../unit/` に置く。
- `nix/tests/default.nix` の `perSystem.checks` に明示的に登録する。
- 実行依存は pkgs から供給し、sandbox の一時領域を利用する。
- 必要な assertion や外部コマンドの失敗を build 失敗として伝播する。テスト未実行を成功扱いにしない。
- Bats / Lua など既存の runtime suite は呼び出して再利用し、同じ assertion を複製しない。
- 共有 fixture は `../fixtures/` に置く。NixOS VM check は Linux にだけ登録する。
- CLI double によるテストと、実際の GUI / service の動作確認を区別する。
- 検証は `nix build .#checks.<system>.<name> --no-link --no-write-lock-file`。
- `nix flake check --no-build` は derivation の評価だけで、ここにあるテストを実行しない。
