# Nix テスト

Nix のテストは、値を評価する単体テストと、ビルド・実行を伴うテストに分けます。
どちらも flake の `checks.<system>.<name>` から実行できます。`checks` は公開入口であり、
nix-unit と競合する別のテストフレームワークではありません。

## 配置と所有境界

| 配置                   | 戻り値・役割                                                                                           | 自動検出                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| `unit/**/*.nix`        | `test...` をキーにした `expr` / `expected` の属性セット。Nix 式、実効 option、package 選択、flake 配線 | `nix/tests/discover.nix` が再帰的に読み込み `nix-unit.tests` へ接続 |
| `build/**/*.check.nix` | check 名をキーとする derivation の属性セット。ビルド・生成物・外部プロセスを検証                       | 同じ scanner が読み込み `checks` へ接続                             |
| `fixtures/`            | テスト用 pkgs、Home Manager / OS 評価関数、hardware module などの共有入力                              | 自動検出せずテストから利用                                          |

テストの分類は本番の `nix/` に揃えます。統合設定・OS 構成は `unit/defaults/`、
アプリは本番 `modules/` と同じ分類の `unit/modules/`、共通キーは `unit/home/keybindings/bindings.nix`、
Windows manifest の契約は CI の jq で直接検証します。
構成テストは `nix/defaults.nix:systemDefaults` を参照し、`platform` と `system` で対象を選択します。
`nix/tests/context.nix` が `fixtures` / `homeConfigurations` / `code` / `files` / `upstream` を共有し、テストは必要な引数だけを受け取ります。
`homeConfigurations` は共通の本番 Home Manager 構成を保持し、同じホストの評価を共有します。
アプリ設定は各 OS の実効 option や正本ファイルを入力とし、生成された設定ファイルや shell 連携へ
反映されることを検証します。共通設定を別途評価して期待値にせず、各 OS の override も対象にします。
同じ option 同士の自己比較を避け、OS 境界・有効化・所有権は独立した assertion にします。
生成ファイルが derivation の場合、unit は生成入力と配線を検証し、実際の生成処理の実行は build が担当します。
unit のファイルは `test...` 属性を持つ nix-unit 形式にし、ファイル名は kebab-case にします。
すべての unit `.nix` と build `.check.nix` を自動検出するため、テスト追加・移動時の個別パス登録は不要です。
unit ファイルが空、テスト・check 名が重複、検出した全体が 0 件の場合は失敗します。
build ファイルは OS 条件で空の属性セットを返せます。build の通常の `.nix` helper は検出しません。
`unit/ownership.nix` と discovery の契約テストが unit / build の検出範囲・重複・空集合を検査します。

テスト定義には fixture・純粋な helper・asset を含め、リポジトリ内のファイルパスや import を書きません。
`source-tree.nix` がリポジトリの資源を再帰的に自動索引し、context が属性で渡します。
資源ごとの手書き catalog やパス登録は不要です。パスを扱うのはこの共通 infrastructure だけです。

- `fixtures.mkHome` / `fixtures.mkHomeWith` は本番と同じ module を自動検出し、型付き option で必要なアプリだけを有効化します。
- `homeConfigurations` は本番と共通の OS 構成、`fixtures.mkDarwin` は Darwin OS module の単独評価に使います。
- `code.*` は Nix ファイルを拡張子なしの属性名で参照し、通常の値・関数として扱います。純粋な factory・renderer もここから利用します。
- `files.*` はファイルパスを保持します。Nix ファイルは拡張子なし、それ以外はファイル名をそのまま使い、ディレクトリは `.__path` で参照します。
- `upstream.<input>.code` / `upstream.<input>.files` は flake input の資源を同じ形式で参照します。例: `upstream.home-manager.code.modules.lib.mcp { inherit lib; }`。外部資源にも import やソース内のパスを指定しません。
- Nix ファイルとディレクトリの属性名が重なる場合、ディレクトリの子属性を維持し、同名ファイルは `.__file` で参照します。`code` では式・関数、`files` ではパスになります。

実 module の設定は評価結果で検証し、`code` 経由で直接呼び出したり mock lib で設定を取り出したりしません。
本番側の純粋な factory・renderer は通常の関数のまま維持します。テストからは `code` で参照するため、個別の import は不要です。

```nix
# unit の例: 必要な context 引数だけを受け取る
{ fixtures, code }:
let
  home = fixtures.mkHome "aarch64-darwin" [
    { programs.wezterm.enable = true; }
  ];
in
{
  testWeztermTheme = {
    expr = home.config.programs.wezterm.settings.color_scheme;
    expected = code.nix.modules.terminals.appearance.theme;
  };
}
```

```nix
# build/example.check.nix: asset も属性から参照する
{ pkgs, files }:
{
  wezterm-lua = pkgs.runCommand "wezterm-lua-check"
    { nativeBuildInputs = [ pkgs.lua ]; }
    ''
      luac -p ${files.nix.modules.terminals.wezterm."wezterm.lua"}
      touch "$out"
    '';
}
```

nix-unit の flake-parts module が `checks.<system>.nix-unit` を自動生成します。
アプリの実行テストは本番の分類に対応する `build/modules/`、独自 package と standalone Darwin の構成ビルドは
`build/defaults/{custom-packages,standalone-darwin-home}.check.nix`、PowerShell formatter は `build/treefmt/powershell.check.nix` に置きます。
実行スクリプトを flake の配線ファイルに直書きしません。
`treefmt` は treefmt-nix の flake-parts module が標準 check として公開します。
設定の正本は `nix/treefmt.nix`、読み込みと開発シェルの配線は `nix/defaults.nix` です。
Unix CLI と GUI の選択は型付き option でアプリを有効化した Home Manager の実効設定で検証し、
OS 固有の連携 package は host の実効設定で検証します。
Windows の標準 package ID / source は CI の jq が `windows/winget/packages.json` を直接検証します。
廃止した package catalog / provider resolution の fixture や生成 manifest 比較は対象にしません。

- `scripts/sh/tests/` は shell / installer の順序、外部コマンドの stub、runtime / artifact 契約を検証します。
- Nix の値 assertion を Bats 内の `nix eval` に追加せず、`unit/` に記載します。
- Nix の構成・package 選択・生成設定の検証はすべて `unit/` / `build/` が担当します。
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
Codex / Hermes の unit は公式 Home Manager 設定と共通 MCP の配線を検証します。
Docker MCP の unit は Linux / macOS の Home Manager package・plugin link・宣言したサーバー選択を検証します。
`docker-mcp` check は固定した公式 Git source と同梱の依存からビルドし、空の HOME で Docker CLI からの
plugin 検出、版の表示、gateway の起動オプションを確認します。Docker daemon や秘密情報は不要です。
Hermes の unit は最終的な `settings.mcp_servers` で Chrome / X API の HTTP 接続先、
Pipedream の OAuth 設定、HTTP サーバーにローカル command がないことを確認します。
共有する native ユーザーサービスの起動、headless browser の操作、API 認証は実機で確認します。

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
`powershell-formatter` と `treefmt` は、nixpkgs の PowerShell 拡張機能に同梱された
PSScriptAnalyzer を Nix store から直接 import します。VS Code 本体は不要です。
更新は nixpkgs input の lock 更新に従い、追加の release metadata input は使いません。
依存 input の取得は build に先行し、formatter の実行中に `Install-Module` を呼びません。
空の HOME でも同じ依存を使用します。`powershell-formatter` は未整形 fixture を整形し、
CRLF・日本語の BOM と二度目の実行で byte / 更新時刻が変わらないことを検証します。
`task test:nix` と Linux の check job は全 checks に含めて実行します。
Linux の container job は `docker/bootstrap-ci-tools/nix.conf` で
`sandbox = true` を設定した tools image を使います。新しい image は公開前に
`check-bootstrap-ci-tools.sh --sandbox` で sandbox 内の build を検証し、各 job は検証済みの
image を immutable digest で再利用します。
全 CI platform は公式の `cache.nixos.org` を public package の取得で優先し、
Numtide mirror は priority 50 の fallback として使います。設定の正本は
`docker/bootstrap-ci-tools/nix.conf` で、認証設定用 adapter も同じ値を読み込みます。
WSL の転送 artifact は workflow run ID ごとに保存し、consumer だけの再実行でも
成功済み producer の出力を再利用します。producer の再実行時は同じ artifact を置き換えます。
CI の format 検査は全 checks 内の `treefmt` にまとめ、同じ検査を別 job では実行しません。
check job の結果も `Bootstrap / Complete` の成功条件に含めます。CI が host の PSGallery module を準備しても、
Nix formatter は host module ではなく固定した store module を使います。
`activationPackage` を checks に登録すれば Home Manager の構成ビルドも検証できますが、
それ自体は activation の実行や、設定値を比較する nix-unit テストを意味しません。

Linux bootstrap CI は hardware fixture を `/etc/nixos/hardware-configuration.nix` に配置し、`x86_64-linux`（`ubuntu-24.04`）で本番 NixOS system と standalone Home Manager activation package を build します。両構成は同じ `systemDefaults.home-manager.sharedModules` を使います。
Darwin CI は `extendModules` で runner の `system.primaryUser` を明示し、`aarch64-darwin`（`macos-15`）で `darwin-rebuild switch` と全 flake checks を実行します。
WSL CI も `platform = "wsl"` を選ぶ本番経路の `nixos-rebuild switch` を実行します。Darwin cask artifact check は CI で実行しません。
workflow の認証・cache の保護・変更分類・集約判定は `scripts/sh/tests/ci_workflow.bats` で実行します。
YAML 構文は `actionlint`、設定適用は対象 platform の rebuild で検証します。
共通の `nix` job は statix の lint を確認し、事前の `nix eval` / `nix flake check --no-build` は実行しません。
`aarch64-linux` は flake の support/output には含まれますが、この workflow には ARM64 Linux runner の native build がありません。
`aarch64-linux` の native build には対応する builder が必要です。
配置変更時には `.github/actions/detect-ci-changes/action.yml` の共有検査・OS 別の分類と、
対応する workflow の実行条件を確認してください。

## Bats の所有境界

`scripts/sh/tests/` は shell / installer の runtime 契約を担当します。Windows の manifest は
独立した管理対象なので、Nix から生成した JSON との一致検査はありません。
Windows の installer と verifier の実行契約は PowerShell / Pester が担当します。

`unit/ownership.nix` は現在のファイル一覧から、再帰的な unit/build 検出の完全一致、
重複したテスト名を検査します。過去の移行時の件数や
廃止したテスト名は固定しません。実行中の移行・backup・rollback 処理を守る
runtime テストは残します。過去の移管履歴は [PR #633](https://github.com/rurusasu/dotfiles/pull/633) を参照してください。

Nix / Bats 間の責務や呼び出しを変更した場合は、全 system の評価、対象 check の build、
`task test:bash` を実行します。Task は `runtime-tests` shell の明示したツールだけで Bats を実行します。
ホストの Nix・curl・PowerShell をテストの PATH に持ち込まず、必要な外部コマンドは各 fixture が用意します。
