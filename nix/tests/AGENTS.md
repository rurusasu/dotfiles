# nix/tests: テストの配置と自動検出

## 責務

- `unit/`: nix-unit が評価する `expr` / `expected` の属性セット。
- `build/`: `*.check.nix` が check 名をキーとする derivation の属性セットを返し、ビルド、生成物比較、外部プロセス実行を検証する。
- `fixtures/`: 共有する pkgs 構築関数や VM 用 module。テストとして登録しない。
- 詳細な実行手順と Bats の責務分類は [README.md](README.md) を参照する。

## 変更時

- 戻り値で unit / build を分け、その下の分類は本番 `nix/` に揃える。統合設定は `defaults/`、アプリは本番と同じ `modules/` の分類に置く。どちらも flake の `checks` 経由で実行する。
- `nix/tests/discover.nix` が `unit/**/*.nix` と `build/**/*.check.nix` を再帰的に自動検出し、`nix/tests/default.nix` が flake に接続する。個別テストの import パス登録・公開一覧は作らない。
- unit はファイル単位の 0 件を失敗させる。build は OS 条件でファイル単位の空集合を返せるが、全体で 0 件・名前の重複はどちらも失敗させる。
- `context.nix` が共有する `fixtures` / `homeConfigurations` / `code` / `files` / `upstream` から必要な引数だけを受け取る。テスト定義には fixture・helper・asset のローカルパスや import を書かない。`source-tree.nix` がリポジトリを自動索引し、個別の資源 catalog は作らない。外部 flake input の helper・asset は `upstream.<input>.code` / `upstream.<input>.files` で参照する。
- Home Manager は `fixtures.mkHome` / `fixtures.mkHomeWith` と型付き option、共通の本番構成は `homeConfigurations`、Darwin OS module は `fixtures.mkDarwin` を使う。純粋な helper は `code.*` の通常の値・関数、asset は `files.*` のファイル・ディレクトリとして参照する。パス処理は共通 infrastructure の責務とし、個別テストの参照をそこへ登録しない。
- 移動時は `code` / `files` の属性参照、README、CI routing、Bats / PowerShell の固定パスを同時に更新する。
- 共通キーは `unit/home/keybindings/bindings.nix`、Windows manifest は CI の jq で直接検証する。unit / build の検出漏れ・重複は `unit/ownership.nix` が検査する。
- 既存の公開 check 名と OS 制約を維持する。VM テストは Linux builder が必要。
- fixture に実際の認証情報や個人データを入れず、実機の設定として適用しない。

## 検証

- 全 system の評価: `nix flake check --all-systems --no-build --no-write-lock-file`。
- 単体テスト: `nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file`。
- ビルドテスト: 対象の `checks.<system>.<name>` を build する。Unix の通常セットは `task test:nix`。
- `--no-build` の成功をテスト成功として報告しない。実機・VM 未実行の範囲を明示する。
