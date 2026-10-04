# Nix テスト

Nix のテストは、値を評価する単体テストと、ビルド・実行を伴うテストに分けます。
どちらも flake の `checks.<system>.<name>` から実行できます。`checks` は公開入口であり、
nix-unit と競合する別のテストフレームワークではありません。

## 配置と所有境界

| 配置        | 戻り値・役割                                                                    | 登録先                                     |
| ----------- | ------------------------------------------------------------------------------- | ------------------------------------------ |
| `unit/`     | `expr` / `expected` の属性セット。Nix 式、実効 option、package 選択、flake 配線 | `nix/flakes/tests.nix` の `nix-unit.tests` |
| `build/`    | ビルド・生成物・外部プロセスを検証する derivation                               | 同ファイルの `checks`                      |
| `fixtures/` | テスト用 pkgs、VM 用 hardware module などの共有入力                             | テストから import                          |

Home Manager の構成テストは `unit/home/`、host の構成テストは `unit/hosts/` に置きます。
unit のファイルは `test...` 属性を持つ nix-unit 形式にし、ファイル名は kebab-case にします。
`unit/ownership.nix` が unit / build の登録漏れ・重複と Bats の責務分類を検査します。

nix-unit の flake-parts module が `checks.<system>.nix-unit` を自動生成します。
`build/` には AeroSpace、Neovim、Ghostty、Windows キー設定生成物、独自 package build、
NixOS VM のテスト本体を置きます。実行スクリプトを flake の配線ファイルに直書きしません。
`package-provider-coverage` は `nix/flakes/packages.nix` で既存の package-support-report
derivation を再利用し、`treefmt` は formatter module が公開します。

- `tests/bash/` は shell / installer の順序、外部コマンドの stub、runtime / artifact 契約を検証します。
- Nix の値 assertion を Bats 内の `nix eval` に追加せず、`unit/` に記載します。
- `nixos_wsl_postinstall.bats` の `nix eval` は、stubbed `nixos-rebuild` 境界内で選択 user と
  `--impure` 伝播を確認する runtime / integration assertion に限ります。
- 実機の activation、service 起動、secret、network は nix-unit の対象外です。
  ビルド・CLI double の成功だけで実機の動作確認が完了したとは扱いません。

## 実行

Unix の `task test` は `task test:nix` を呼びます。生成キー設定の整合性検査に続いて、
現在の system の powershell-formatter、nix-unit、custom-package-builds、aerospace-workspace-cycle、
darwin-default-shell、neovim-native、ghostty-config を一つの `nix build` にまとめます。同じ flake の評価を7回繰り返しません。
Windows の `task test` は PowerShell テストを実行します。

```bash
# 全 system の flake 出力を評価する。テスト本体は実行しない
nix flake check --all-systems --no-build --no-write-lock-file

# 通常のローカル検証セット（Unix）
task test:nix

# 単体テストだけを実行（Apple Silicon の例）
nix build .#checks.aarch64-darwin.nix-unit --no-link --no-write-lock-file

# CI と同じ単体テスト・独自 package build の個別実行例（各対象の builder が必要）
nix build .#checks.x86_64-linux.nix-unit --no-link --no-write-lock-file
nix build .#checks.x86_64-linux.powershell-formatter --no-link --no-write-lock-file
nix build .#checks.x86_64-linux.custom-package-builds --no-link --no-write-lock-file
nix build .#checks.aarch64-darwin.custom-package-builds --no-link --no-write-lock-file

# ビルド・実行テストを指定する例
nix build .#checks.aarch64-darwin.aerospace-workspace-cycle --no-link --no-write-lock-file

# PowerShell formatter を空 HOME・ダウンロード禁止で実行し、BOM/CRLF/冪等性を確認
nix build .#checks.aarch64-darwin.powershell-formatter --no-link --no-write-lock-file

# repository 全体の format gate（対象 system の builder が必要）
nix build .#checks.aarch64-darwin.treefmt --no-link --no-write-lock-file

# 現在の system の checks 全体を build（Linux では NixOS VM も含む）
nix flake check --no-write-lock-file

# Linux builder で NixOS VM のテストを実行
nix build .#checks.x86_64-linux.bootstrap-nixos-vm --no-link --no-write-lock-file
```

`nix flake check --no-build` は評価確認です。nix-unit assertion や実行テストの成功は、
対象 check の build 結果で確認します。Nix が既存の成功済み出力を再利用する場合もあります。
`powershell-formatter` と `treefmt` は、公式 PSScriptAnalyzer 1.22.0 release archive を
hash 固定した Nix input として取得し、Nix store の module manifest を直接 import します。
依存 input の取得は build に先行し、formatter の実行中に `Install-Module` を呼びません。
空の HOME でも同じ依存を使用します。`powershell-formatter` は未整形 fixture を整形し、
CRLF・日本語の BOM と二度目の実行で byte / 更新時刻が変わらないことを検証します。
通常の `task test:nix` と Linux/Darwin CI は `powershell-formatter` を個別に build しますが、
全 checks の build とは範囲が異なります。Linux CI は `docker/bootstrap-ci-tools/nix.conf` で
`sandbox = true` を設定した tools image を使います。新しい image は公開前に
`check-bootstrap-ci-tools.sh --sandbox` で sandbox 内の build を検証し、各 job は検証済みの
image を immutable digest で再利用します。
CI の format job は `nix fmt -- --fail-on-change` を実行し、`treefmt` derivation や
`powershell-formatter` の build を代替しません。CI が host の PSGallery module を準備しても、
Nix formatter は host module ではなく固定した store module を使います。
`activationPackage` を checks に登録すれば Home Manager の構成ビルドも検証できますが、
それ自体は activation の実行や、設定値を比較する nix-unit テストを意味しません。

Linux bootstrap CI は `x86_64-linux`（`ubuntu-24.04`）の `linux-build` job で、
アプリを含む OS 構成、standalone Home Manager 構成、nix-unit と各 build check を一つの `nix build` に渡します。
Darwin bootstrap CI も `aarch64-darwin`（`macos-15`）で、アプリを含む OS 構成と native check をまとめて build します。
`hermes-bootstrap-tests` は bootstrap 本体と同じ軽量 Python 環境で、固定した公式 Hermes source の API を使います。
公式 full package は `hermes-runtime` で別に検証し、Hermes・依存 pin・flake wiring・関連 CI の変更時と
手動 CI 実行時に Darwin で build します。公式依存は上書きしません。Darwin CI では無関係な shell 変更で音声/ML 依存を再ビルドさせません。
Linux の NixOS VM check は独立した runner で実行し、成果物を受け取らない `linux-build` の終了を待ちません。
両 job は引き続き Bootstrap / Complete の必須成功条件です。
共通の `nix` job は lint と format だけを確認し、事前の `nix eval` / `nix flake check --no-build` は実行しません。
`aarch64-linux` は flake の support/output には含まれますが、この workflow には ARM64 Linux runner の native build がありません。
NixOS VM は Linux 限定です。`aarch64-linux` の native build には対応する builder が必要で、
Darwin での成功は Linux / VM の実行結果を代替しません。
配置変更時には `ci/path-routing.json`、`ci/bootstrap-path-routing.json`、
`ci/job-path-routing.json` とその回帰テストも更新してください。

## Bats の所有境界と完全分類

`tests/bash/package_catalog.bats` は6件で、installer/runtime、generated artifact、
署名済みbundleの独自契約だけを含みます。Nix値/source-shape assertionsは移管済みです。
番号は現在の `@test` 出現順です。
CIのexport checkはWinget/npm/pnpm JSON全体を生成してcommitted filesとJSON dataとして比較するため、
個別metadata grepは重ねません。nix-unit ownership assertionはBats一覧とREADME分類の完全一致を検査します。

### Bats runtime / artifact contracts（6件）

| 番号 | テスト                                                                      | native suite に残す契約                                                          |
| ---: | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
|    1 | `DeepSeek Harness native builds are pre-approved for pnpm global installs`  | rendered installer behavior on Linux/macOS                                       |
|    2 | `DeepSeek Harness is reinstalled when the native build approval changes`    | installer decision/runtime behavior                                              |
|    3 | `pnpm v11 global installs skip packages present in the global manifest`     | pnpm runtime skip behavior                                                       |
|    4 | `winget export matches committed Windows manifest data`                     | complete generated Winget/npm/pnpm artifact data, independent of JSON formatting |
|    5 | `Darwin Raycast artifact has the declared identity and trusted signature`   | built app identity, codesign, Gatekeeper                                         |
|    6 | `Darwin Discord keeps staged modules outside its signed application bundle` | built layout, launcher path, app identity and signatures                         |

上記の Darwin artifact 2件は `Bootstrap / Darwin` の native runner が限定実行します。
Linux Bats での codesign 不在による skip は、この2件の成功として扱いません。
Mac の専用 step は Nix・codesign・plutil・spctl と対象2件の存在を確認し、欠落・失敗を伝播します。
既存の artifact assertion を再利用し、Bats 全体を Mac で重複実行しません。
package_catalog.bats の変更も native Darwin job を起動します。

### 現行テストの所有境界

`unit/ownership.nix` は現在のファイル一覧から、再帰的な unit/build 登録の完全一致、
重複したテスト名、Bats 内の `nix eval` 所有者を検査します。過去の移行時の件数や
廃止したテスト名は固定しません。実行中の移行・backup・rollback 処理を守る
runtime テストは残します。過去の移管履歴は [PR #633](https://github.com/rurusasu/dotfiles/pull/633) を参照してください。

Nix / Bats 間の責務や呼び出しを変更した場合は、上記の全 system の評価と対象 check の build に加えて、
変更対象に絞った `bats` 実行または `task test:bash` で関連する runtime 契約を確認します。
package catalog の変更時は focused exact command として `bats tests/bash/package_catalog.bats` も実行する。
Nix または `jq` がないため Bats ケースが `skip` された場合、検証成功とは扱わない。必要なツールを
用意して再実行するか、未検証として停止する。
