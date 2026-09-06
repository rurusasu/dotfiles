# Home Manager テスト

`nix/tests/home/` は、Home Manager module と OS 別の構成を Nix-native に検査する権威あるテスト層です。
構造・import 境界だけでなく、固定した入力で `homeManagerConfiguration` を組み合わせた実効 option、
package、session variable も `nix-unit` で評価します。

## 所有境界

- Nix expression、Home Manager option、package 選択、session variable、flake output は `nix/tests/` に記載する。
- `tests/bash/` は shell/installer の順序、外部コマンドの stub、runtime/integration 契約に限定する。
- Nix 設定の値を `nix eval` で確認するだけの Bats テストは追加しない。既存の同種テストも対応する Nix test に移す。
- activation、実機のサービス起動、secret、network は Nix-unit の対象外とし、必要な runtime 契約だけを Bats または CI の実機ジョブで検査する。

## ファイル規則

- ファイル名は `<topic>.nix` の kebab-case とする。
- 1ファイル1責務とし、テストは `nix-unit` 形式の attrset にする。
- 属性名は `test` で始め、各テストは `expr` と `expected` を持つ。
- テスト内のパスはテストファイルからの相対 Nix path を使う。
- 新しいテストは `nix/flakes/tests.nix` の `perSystem.nix-unit.tests` に登録する。

## 実行

```bash
# Nix configuration の authoritative check
nix flake check --all-systems --no-write-lock-file

# 現在の system で nix-unit を実行する焦点確認
nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').nix-unit \
  --no-link --no-write-lock-file
```

`--no-build` は flake graph の評価だけで、nix-unit assertion の実行結果を保証しません。
変更時は focused build と `nix flake check` の両方を実行してください。Linux 専用 check を
Darwin から直接 build せず、`x86_64-linux` / `aarch64-linux` の CI runner で実行します。
