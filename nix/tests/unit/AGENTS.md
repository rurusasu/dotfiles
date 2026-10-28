# unit: nix-unit の値テスト

- Nix 式、Home Manager / host の実効 option、package 選択、flake の配線を検証する。
- 統合設定・OS 構成は `defaults/`、アプリは本番 `nix/modules/` と同じ分類の `modules/` に置く。共通キーは `home/keybindings/bindings.nix`、登録契約は `ownership.nix` が担当する。Windows manifest は CI の jq で直接検証する。
- 各ファイルは `test...` 属性を持つ属性セットを返し、各テストに `expr` と `expected` を定義する。
- 共通 context の `inputs` / `fixtures` / `homeConfigurations` / `code` / `files` / `upstream` から必要な引数だけを受け取る。pkgs は `fixtures.mkPkgs`、helper は `code.*`、asset は `files.*` を使い、fixture を含むローカルパス・import をテスト定義へ書かない。資源は `source-tree.nix` が自動索引し、手書きの catalog は追加しない。外部 flake input は `upstream.<input>.code` / `upstream.<input>.files` を使う。
- `nix/tests/discover.nix` がすべての通常ファイル `*.nix` を再帰的に自動検出する。個別の import パス登録は不要。空のファイル・名前の重複・全体で 0 件は失敗させる。
- module の評価は `fixtures.mkHome` / `fixtures.mkHomeWith` と型付き option を使う。共通の本番構成は `homeConfigurations` を共有し、実 module の個別参照・直接呼び出しや mock lib での評価はしない。純粋な factory・renderer は `code.*` の通常の関数として検証する。
- helper だけのファイルをここに追加しない。共有入力・関数は `nix/tests/fixtures/` に置く。
- テスト用 derivation を比較対象にすることは可能だが、そのビルドや外部プロセスの成功を主張しない。
- shell の挙動やサービス起動は `../build/`、Bats、実機 CI の責務。
- 構成値は可能な限り評価結果で比較する。source-shape 検査は import 境界・登録漏れなど構造自体が契約の場合に限定する。
- 検証は `nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file`。
