# build: ビルド・実行テスト

- 実行テストは `*.check.nix` に置き、check 名をキーとする derivation の属性セットを返す。`expr` / `expected` の単体テストは `../unit/` に置く。
- アプリの実行テストは本番 `nix/modules/` と同じ分類の `modules/`、構成ビルドは `defaults/`、PowerShell formatter は `treefmt/powershell.check.nix` に置く。
- `nix/tests/discover.nix` が `*.check.nix` を再帰的に自動検出する。個別の import パス登録は不要。通常の `.nix` helper は自動検出しない。
- OS 条件によりファイル単位で空の属性セットを返せる。全体で 0 件・check 名の重複は失敗させる。
- 共通 context の `fixtures` / `homeConfigurations` / `code` / `files` / `upstream` と build 用の `pkgs` などから必要な引数だけを受け取る。fixture・helper・asset のローカルパス・import はテスト定義へ書かず、helper は `code.*`、asset は `files.*` で参照する。資源は共通 infrastructure が自動索引し、個別の資源 catalog は作らない。外部 flake input の helper・asset は `upstream.<input>.code` / `upstream.<input>.files` で参照する。
- Home Manager は `fixtures.mkHome` / `fixtures.mkHomeWith` と型付き option、Darwin OS module は `fixtures.mkDarwin` を使い、実 module を個別参照しない。純粋な factory・renderer は `code.*` の通常の関数として利用する。
- 実行依存は pkgs から供給し、sandbox の一時領域を利用する。
- 必要な assertion や外部コマンドの失敗を build 失敗として伝播する。テスト未実行を成功扱いにしない。
- Bats / Lua など既存の runtime suite は呼び出して再利用し、同じ assertion を複製しない。
- 共有 fixture は `../fixtures/` に置く。
- CLI double によるテストと、実際の GUI / service の動作確認を区別する。
- 検証は `nix build .#checks.<system>.<name> --no-link --no-write-lock-file`。
- `nix flake check --no-build` は derivation の評価だけで、ここにあるテストを実行しない。
