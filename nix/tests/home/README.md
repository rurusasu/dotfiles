# Home Manager テスト

`nix/tests/` は、Home Manager module、host layout、OS 別の構成を Nix-native に検査する権威あるテスト層です。
構造・import 境界だけでなく、固定した入力で `homeManagerConfiguration` を組み合わせた実効 option、
package、session variable も `nix-unit` で評価します。

## 所有境界

- Nix expression、Home Manager option、package 選択、session variable、flake output は `nix/tests/` に記載する。
- `tests/bash/` は shell/installer の順序、外部コマンドの stub、runtime/integration 契約に限定する。
- Nix 設定の値を `nix eval` で確認するだけの Bats テストは追加しない。既存の同種テストも対応する Nix test に移す。
  ただし既存の `tests/bash/package_catalog.bats` は下記の分類済み一時例外であり、
  `nixos_wsl_postinstall.bats` の `nix eval` は、stubbed `nixos-rebuild` 境界内で選択 user と
  `--impure` 伝播を実 Nix eval で確認する runtime/integration assertion に限る。
- activation、実機のサービス起動、secret、network は Nix-unit の対象外とし、必要な runtime 契約だけを Bats または CI の実機ジョブで検査する。

## ファイル規則

- ファイル名は `<topic>.nix` の kebab-case とする。
- 1ファイル1責務とし、テストは `nix-unit` 形式の attrset にする。
- 属性名は `test` で始め、各テストは `expr` と `expected` を持つ。
- テスト内のパスはテストファイルからの相対 Nix path を使う。
- 新しいテストは `nix/flakes/tests.nix` の `perSystem.nix-unit.tests` に登録する。
- host の entrypoint/configuration の分割は `nix/tests/hosts/` に記載する。

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

## Bats の一時例外と完全分類

`tests/bash/package_catalog.bats` の46ケースは、Nix の所有境界を曖昧にしないため、次のとおり
全ケースを分類する。番号はファイル内の `@test` の出現順であり、Nix 側の所有チェックは
`tests/bash/*.bats` を動的に列挙して `nix eval` を含むファイルを
`["nixos_wsl_postinstall.bats" "package_catalog.bats"]` に固定する。

### 正当な Bats runtime / artifact 契約（5件）

以下は、実行時の stub、生成物、または署名済み artifact を検証するための Bats 所有です。

| 番号 | テスト |
| ---: | --- |
| 17 | `pnpm v11 global installs skip packages present in the global manifest` |
| 22 | `winget export reproduces committed Windows manifests byte-for-byte` |
| 33 | `Darwin Raycast artifact has the declared identity and trusted signature` |
| 34 | `Darwin Discord keeps staged modules outside its signed application bundle` |
| 35 | `generated Windows manifest contains Discord` |

### 一時的な catalog / Nix / source-shape 例外（41件）

対象範囲は `1-16, 18-21, 23-32, 36-46` で、既存の package catalog、Nix provider、source shape の互換性を守るための
分類済み例外である。これらを新しい Bats の所有境界として拡張せず、追加・変更時は対応する
Nix-native test へ移行する。

| 番号 | テスト |
| ---: | --- |
| 1 | `Claude and TablePlus are not managed by dotfiles` |
| 2 | `catalog defines provider coverage outputs` |
| 3 | `host package set includes GitHub CLI for Darwin and Linux` |
| 4 | `catalog accepts an explicitly maintained Codex package` |
| 5 | `Codex package input is available for supported Nix systems` |
| 6 | `repository Codex output follows the maintained package input` |
| 7 | `Codex support metadata records the external provider` |
| 8 | `Hermes Desktop uses the official Homebrew cask only with the Hermes profile` |
| 9 | `Hermes Desktop Docker launcher is a Darwin Hermes package` |
| 10 | `Hermes Docker CLI is a Darwin Hermes package` |
| 11 | `Hermes Desktop is absent from default package outputs` |
| 12 | `catalog rejects incomplete metadata and invalid active Nix packages` |
| 13 | `Node.js follows the current nixpkgs major` |
| 14 | `DeepSeek Harness is managed as a cross-platform pnpm package` |
| 15 | `DeepSeek Harness native builds are pre-approved for pnpm global installs` |
| 16 | `DeepSeek Harness is reinstalled when the native build approval changes` |
| 18 | `cross-platform applications are not classified as Windows-only` |
| 19 | `Docker declares Homebrew cask Darwin and Linux system providers` |
| 20 | `true Windows-only packages carry unsupported reasons` |
| 21 | `support report derivation and CI gate are wired` |
| 23 | `missing providers require an explicitly reviewed unsupported reason` |
| 24 | `catalog Winget packages preserve ID-keyed metadata` |
| 25 | `macOS desktop apps include Dia and Orca migration metadata` |
| 26 | `Visual Studio Code uses the unmodified nixpkgs application with migration metadata` |
| 27 | `Darwin routes Nix GUI apps to system packages and keeps commands in Home Manager` |
| 28 | `Arc remains Windows-only and Dia remains macOS-only` |
| 29 | `Discord preserves Windows and Linux providers while declaring a Nix Darwin GUI migration` |
| 30 | `Google Chrome preserves its Windows provider while declaring a Nix Darwin GUI migration` |
| 31 | `Raycast preserves reviewed Windows and Linux unsupported reasons while declaring a Nix Darwin GUI migration` |
| 32 | `Tart preserves Apple Silicon-only unsupported reasons while declaring a Nix command migration` |
| 36 | `WezTerm uses the Nix Darwin application and preserves nightly cask migration metadata` |
| 37 | `Ollama uses the Nix Darwin service package with legacy cask migration metadata` |
| 38 | `Darwin GUI promotions use custom products instead of same-named nixpkgs packages` |
| 39 | `custom Darwin package derivations preserve vendor bundles` |
| 40 | `Docker Desktop has no custom Darwin package or provider candidate` |
| 41 | `ChatGPT uses the nixpkgs Darwin application with legacy cask migration metadata` |
| 42 | `ChatGPT Linux package is wired as a reproducible Nix derivation` |
| 43 | `ChatGPT Linux package supplies Qt runtimes and ignores optional musl modules` |
| 44 | `ChatGPT Linux package uses the normal Nix output layout` |
| 45 | `Warp is removed from the package catalog` |
| 46 | `terminal keybinding helpers have platform-scoped providers` |

必須検証は、Nix の authoritative check（`nix flake check --all-systems --no-write-lock-file` と
focused `nix-unit` build）に加えて `task test:bash`、または変更対象に絞った `bats` 実行を行うこと。
package catalog の変更時は focused exact command として `bats tests/bash/package_catalog.bats` も実行する。
Nix または `jq` がないため Bats ケースが `skip` された場合、検証成功とは扱わない。必要なツールを
用意して再実行するか、未検証として停止する。
