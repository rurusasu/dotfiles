# unit: nix-unit の値テスト

- Nix 式、Home Manager / host の実効 option、package 選択、flake の配線を検証する。
- 各ファイルは `test...` 属性を持つ属性セットを返し、各テストに `expr` と `expected` を定義する。
- 入力が必要なら `{ inputs }:` を受け取り、pkgs は `../fixtures/packages.nix` を利用する。
- `nix/tests/default.nix` の `perSystem.nix-unit.tests` に明示的に登録する。
- helper だけのファイルをここに追加しない。共有入力・関数は `../fixtures/` に置く。
- テスト用 derivation を比較対象にすることは可能だが、そのビルドや外部プロセスの成功を主張しない。
- shell の挙動やサービス起動は `../build/`、Bats、実機 CI の責務。
- 構成値は可能な限り評価結果で比較する。source-shape 検査は import 境界・登録漏れなど構造自体が契約の場合に限定する。
- 検証は `nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file`。
