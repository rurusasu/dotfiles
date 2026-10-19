# Nix テスト

Nix のテストは、値を評価する単体テストと、ビルド・実行を伴うテストに分けます。
どちらも flake の `checks.<system>.<name>` から実行できます。`checks` は公開入口であり、
nix-unit と競合する別のテストフレームワークではありません。

## 配置と所有境界

| 配置        | 戻り値・役割                                                                    | 登録先                                      |
| ----------- | ------------------------------------------------------------------------------- | ------------------------------------------- |
| `unit/`     | `expr` / `expected` の属性セット。Nix 式、実効 option、package 選択、flake 配線 | `nix/tests/default.nix` の `nix-unit.tests` |
| `build/`    | ビルド・生成物・外部プロセスを検証する derivation                               | 同ファイルの `checks`                       |
| `fixtures/` | テスト用 pkgs、NixOS hardware module などの共有入力                             | テストから import                           |

Home Manager の構成テストは `unit/home/`、host の構成テストは `unit/hosts/` に置きます。
unit のファイルは `test...` 属性を持つ nix-unit 形式にし、ファイル名は kebab-case にします。
`unit/ownership.nix` が unit / build の登録漏れ・重複と Bats の責務分類を検査します。

nix-unit の flake-parts module が `checks.<system>.nix-unit` を自動生成します。
`build/` には AeroSpace、Neovim、Ghostty/WezTerm 設定、独自 package build を置きます。
実行スクリプトを flake の配線ファイルに直書きしません。
`treefmt` は formatter module が公開します。
Unix CLI の選択は `nix/modules/tools.nix` と各設定 module を組み合わせた
Home Manager の実効設定で検証し、GUI / OS 固有 package は host の実効設定で検証します。
Windows の install / verifier metadata は独立した `windows/winget/packages.json` を直接評価します。
廃止した package catalog / provider resolution の fixture や生成 manifest 比較は対象にしません。

- `tests/bash/` は shell / installer の順序、外部コマンドの stub、runtime / artifact 契約を検証します。
- Nix の値 assertion を Bats 内の `nix eval` に追加せず、`unit/` に記載します。
- Nix の構成・package 選択・生成設定の検証はすべて `unit/` / `build/` が担当します。
  `tests/python/` は Python の処理や外部コマンドの実行を検証し、本番設定の一覧や値を複製しません。
- 実機の activation、service 起動、secret、network は nix-unit の対象外です。
  ビルド・CLI double の成功だけで実機の動作確認が完了したとは扱いません。

## 実行

Unix の `task test` は `task test:nix` を呼びます。CI と同じ
`nix flake check --no-write-lock-file --print-build-logs` で、現在の system に登録された
すべての check を実行します。check 名のリストや system 判定を呼び出し側で管理しません。
対象には nix-unit、独自 package build、AeroSpace、Neovim、WezTerm、Docker Desktop、
PowerShell formatter、treefmt を含み、Darwin では standalone Home Manager の構成ビルドも含みます。
Docker Desktop の初期設定は生成された activation を CLI double で実行し、再実行、失敗時の再試行、
既存の `md5` パスとの衝突を検証します。実機の Docker Desktop 起動は installer の検証対象です。
Windows の `task test` は PowerShell テストを実行します。

Darwin / Linux の `custom-package-builds` は `chatgpt-desktop` check も含み、公式アプリと同梱 CLI の
ビルド・CLI 起動、および Linux の desktop entry と upstream tmpfiles 規則の一致を確認します。
GUI の起動・ログイン・操作はこの check の対象外で、各 OS の実機で確認します。
Darwin の `darwin-bundled-app-cleanup` は、一時ディレクトリ内のアプリを使って
付属アプリの削除・bundle ID の検証・対象外データの保持・再実行を検証します。
`hermes-configuration` は Linux / Darwin 向けに生成した bootstrap manifest を実際の parser で検証し、
Compose sidecar の localhost 公開・接続先・要求 timeout・認証データの mount を確認します。
プロファイル名・commit 値・1Password item の一覧はテスト側に複製しません。

```bash
# 全 system の flake 出力を評価する。テスト本体は実行しない
nix flake check --all-systems --no-build --no-write-lock-file

# CI と共通の全 checks 実行（Unix）
task test:nix

# Taskfile を介さず現在の system の全 checks を実行する
nix flake check --no-write-lock-file --print-build-logs

# 障害調査で単体テストだけを実行（Apple Silicon の例）
nix build .#checks.aarch64-darwin.nix-unit --no-link --no-write-lock-file
```

`nix flake check --no-build` は評価確認です。nix-unit assertion や実行テストの成功は、
対象 check の build 結果で確認します。Nix が既存の成功済み出力を再利用する場合もあります。
`powershell-formatter` と `treefmt` は、PowerShell Gallery の最新版 URL を Nix input として
取得し、Nix store の module manifest を直接 import します。バージョンはコードに固定せず、
`flake.lock` が取得内容を記録します。更新は `nix flake update psscriptanalyzer` で行います。
依存 input の取得は build に先行し、formatter の実行中に `Install-Module` を呼びません。
空の HOME でも同じ依存を使用します。`powershell-formatter` は未整形 fixture を整形し、
CRLF・日本語の BOM と二度目の実行で byte / 更新時刻が変わらないことを検証します。
`task test:nix` と Linux の check job は全 checks に含めて実行します。
Linux の container job は `docker/bootstrap-ci-tools/nix.conf` で
`sandbox = true` を設定した tools image を使います。新しい image は公開前に
`check-bootstrap-ci-tools.sh --sandbox` で sandbox 内の build を検証し、各 job は検証済みの
image を immutable digest で再利用します。
CI の format 検査は全 checks 内の `treefmt` にまとめ、同じ検査を別 job では実行しません。
check job の結果も `Bootstrap / Complete` の成功条件に含めます。CI が host の PSGallery module を準備しても、
Nix formatter は host module ではなく固定した store module を使います。
`activationPackage` を checks に登録すれば Home Manager の構成ビルドも検証できますが、
それ自体は activation の実行や、設定値を比較する nix-unit テストを意味しません。

Linux bootstrap CI は `x86_64-linux`（`ubuntu-24.04`）で本番 NixOS system と standalone Home Manager activation package を build します。
Darwin CI は `aarch64-darwin`（`macos-15`）の runner で `darwin-rebuild switch` と全 flake checks を実行します。
WSL CI も本番経路の `nixos-rebuild switch` を実行します。個別の Hermes Python suite や Darwin cask artifact check は CI で実行しません。
Python unittest suite は CI の gate から外し、workflow 検証は `actionlint`、設定適用は対象 platform の rebuild で行います。
共通の `nix` job は statix の lint を確認し、事前の `nix eval` / `nix flake check --no-build` は実行しません。
`aarch64-linux` は flake の support/output には含まれますが、この workflow には ARM64 Linux runner の native build がありません。
`aarch64-linux` の native build には対応する builder が必要です。
配置変更時には `.github/actions/detect-ci-changes/action.yml` の共有検査・OS 別の分類と、
対応する workflow の実行条件を確認してください。

## Bats の所有境界

`tests/bash/` は shell / installer の runtime 契約を担当します。Windows の manifest は
独立した管理対象なので、Nix から生成した JSON との一致検査はありません。
Windows の installer と verifier の実行契約は PowerShell / Pester が担当します。

`unit/ownership.nix` は現在のファイル一覧から、再帰的な unit/build 登録の完全一致、
重複したテスト名、Bats 内の `nix eval` 所有者を検査します。過去の移行時の件数や
廃止したテスト名は固定しません。実行中の移行・backup・rollback 処理を守る
runtime テストは残します。過去の移管履歴は [PR #633](https://github.com/rurusasu/dotfiles/pull/633) を参照してください。

Nix / Bats 間の責務や呼び出しを変更した場合は、全 system の評価と対象 check の build に加えて、
変更対象に絞った `bats` 実行または `task test:bash` で関連する runtime 契約を確認します。
