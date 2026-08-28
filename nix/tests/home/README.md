# Home Manager テスト

## 対象

`nix/tests/home/` は Home Manager の構造・import 境界・評価可能な設定を検査する。
システムの activation、実機依存の動作、秘密情報は対象外とする。

## ファイル規則

- ファイル名は `<topic>.nix` の kebab-case とする。
- 1ファイル1責務とし、import 境界・OS 入口・設定評価などの単位で分ける。
- テストは `nix-unit` 形式の attrset とし、属性名は `test` で始める。
- 各テストは `expr` と `expected` を持ち、評価結果を直接比較する。
- テスト内のパスはテストファイルからの相対 Nix path を使う。

## 実行規則

- テストは純粋・決定的に保つ。ネットワーク、secret、環境依存の値、Home Manager activation を使わない。
- 外部コマンドを起動せず、必要な検査は Nix 式で実装する。
- 新しいテストは `nix/flakes/tests.nix` の `perSystem.nix-unit.tests` に登録する。
- 標準実行は `nix flake check` とし、全対応 system の確認には `nix flake check --all-systems` を使う。
- テスト変更時は対象テストと `nix flake check` を実行する。
