# GitHub Actions Platform Routing Design

> **Status:** Historical design. The obsolete WezTerm installer path mentioned in this document was removed; current routing follows the declarative nix-darwin Homebrew cask configuration.

## Goal

GitHub Actions の重い build/E2E を変更の実際の処理経路に合わせて選択し、Linux、Darwin、WSL、Windows の検証境界を失わずに不要な実行時間を削減する。

## Context

このリポジトリではトップレベルディレクトリと実行プラットフォームが一対一に対応しない。

- `nix/packages/sets.nix` は Linux、Darwin、WSL、Windows package catalog に波及する。
- `nix/home/common.nix` は Linux、Darwin、WSL で共有される。
- Windows の WSL handler は Windows host から WSL guest の NixOS rebuild を起動する。
- Chezmoi の executable script は設定配布だけでなく、OS ごとの install/rebuild を実行する。
- Hermes の Taskfile と Compose は shell、PowerShell、複数 Docker image を横断する。

したがって、`nix/**`、`scripts/**`のようなディレクトリ単位ではなく、変更パスから処理クラスタと対象プラットフォームを導出する。

## Platform Model

change detector は次の4プラットフォームを独立した boolean として出力する。

| Output    | Runtime boundary                                                    |
| --------- | ------------------------------------------------------------------- |
| `linux`   | Ubuntu、Debian、native NixOS、System Manager、Linux Home Manager    |
| `darwin`  | macOS、nix-darwin、Home Manager、Homebrew                           |
| `wsl`     | Windows host の WSL orchestration と NixOS-WSL guest                |
| `windows` | native PowerShell、winget/npm/pnpm、Windows Chezmoi、Docker Desktop |

WSL は Linux や Windows の別名にしない。WSL entrypoint の変更は、必要に応じて `wsl=true` と `windows=true` の両方を返す。

## Processing Clusters

platform output に加えて、次の処理クラスタを独立して出力する。

| Output            | Responsibility                                                |
| ----------------- | ------------------------------------------------------------- |
| `contract`        | workflow、routing、Taskfile、静的な呼び出し順序の高速検証     |
| `nix`             | Nix evaluation、package build、system configuration build     |
| `chezmoi`         | template render、OS selector、executable Chezmoi script       |
| `hermes`          | Hermes bootstrap、Compose、agent/browser/browser-mcp/xapi-mcp |
| `devcontainer`    | devcontainer image と editor/tmux bootstrap                   |
| `package_catalog` | package SSOT、generated Windows manifests、provider report    |

1つの変更は複数のplatform/clusterへ属してよい。たとえば`nix/packages/sets.nix`は4プラットフォームすべてと、`nix`、`package_catalog`、`chezmoi`を有効化する。

## Considered Approaches

### Workflowごとの`on.paths`だけを調整する

変更量は少ないが、同じ依存関係を複数workflowへ複製する。required workflowが起動しないとcheckが`expected`のまま残る問題も解消しないため採用しない。

### 単一orchestratorから全reusable workflowを呼び出す

routingの重複は最小になるが、既存job名、artifact、rulesetとの互換性を一度に変更する大規模migrationになる。今回の効率化に対して変更リスクが高いため採用しない。

### 共通detectorを既存workflowへ段階導入する

manifestとdetectorをSSOTにしつつ、既存workflow名とrequired contextを維持できる。最初に実行時間の大きいplatform jobへ導入し、軽量workflowは既存構造を保てるため、この方式を採用する。

## Components

### Routing manifest

`ci/path-routing.json`を変更パターンとoutputのSSOTにする。JSONは標準ライブラリだけでテストでき、PowerShellとPythonの追加moduleを必要としない。

各ruleは次の形式を持つ。

```json
{
  "patterns": ["nix/packages/sets.nix"],
  "outputs": ["linux", "darwin", "wsl", "windows", "nix", "chezmoi", "package_catalog"]
}
```

patternはリポジトリ相対pathに対するGit風globとして評価する。`*`は1 path segment、`**`は複数segmentに一致する。manifest自身、detector、detector tests、routing workflowを変更した場合は安全側へ倒し、全outputを有効化する。

### Change detector

`scripts/python/detect_ci_changes.py`を純粋なrouting engineにする。

- stdinまたは明示したfileから改行区切りの変更pathを受け取る。
- `ci/path-routing.json`を読み込む。
- 全outputをJSONとしてstdoutへ出す。
- `--github-output PATH`指定時は、同じbooleanをGitHub Actions output形式でも書き込む。
- pathがどのruleにも一致しなくても異常終了しない。重いplatform jobは起動せず、`contract`は常に実行する。
- manifest不正、未知output、絶対path、`..`を含むpathは明示的に失敗させる。

### Composite action

`.github/actions/detect-ci-changes/action.yml`がGitHub eventからbase/head SHAを受け取り、`git diff --name-only`とdetectorを接続する。`workflow_dispatch`では全outputをtrueにし、手動実行が従来どおり全検証になるようにする。

### Contract CI

`.github/workflows/ci-contract.yml`を軽量な常時実行workflowとして追加する。

- routing detectorのPython unit tests
- `tests/python`全体
- CI routingを検証するBats
- `actionlint`

このworkflowは重いNix build、Docker build、OS bootstrapを行わない。`tests/bash/**`を変更しただけで`Nix CI`や`devcontainer CI`が起動する現在の過剰実行を置き換える。

## Existing Workflow Integration

### Protected Bootstrap E2E

workflow自体は全PRで起動し、required/aggregate contextを失わない。最初に`changes` jobを実行し、Windows jobは`windows`、macOS jobは`darwin`のときだけ実行する。

aggregate jobは`always()`で実行し、各platform jobについて`success`または`skipped`のみを許可する。これにより無関係なPRでも`Protected Bootstrap E2E` contextは成功として報告される。

### Bootstrap Build

Linux jobは`linux`、Darwin jobは`darwin`でgateする。`flake.nix`、`flake.lock`、shared package/home filesはmanifestによって両方を有効化する。complete jobは`success`と`skipped`を受理する。

### Nix CI

workflow-level path filterから一律の`scripts/sh/**`と`tests/bash/**`を除外する。Nix derivationが`builtins.readFile`する次のscriptだけをNix triggerとして残す。

- `scripts/sh/dcnvim.sh`
- `scripts/sh/install-wezterm-nightly.sh`
- `scripts/sh/uninstall-arc-browser.sh`

Nix関連BatsはContract CIで実行し、Nix buildはNix outputを変える変更に限定する。

### Hermes Bootstrap Tests

triggerへ次を追加する。

- `docker/hermes-xapi-mcp/**`
- `scripts/sh/hermes-agent.sh`
- `scripts/powershell/handlers/Handler.HermesAgent.ps1`
- `tests/python/test_xapi_image_contract.py`

Hermes workflowはxapi image contract testを実行する。Composeまたは共通bootstrap変更はrouting manifestでLinux、Darwin、WSL、Windowsへ伝播させる。

### Chezmoi CI

現在requiredの次のjob名は変更しない。

- `Lint (Pester chezmoi)`
- `Format (.tmpl BOM check)`
- `Render guard (op unauthenticated)`

workflow-level PR path filterも追加しない。重複している同一Chezmoi Pester suiteは1回へ統合するが、required job contextは維持する。

### WSL and Windows workflows

`scripts/powershell/handlers/Handler.NixOSWSL.ps1`、`Handler.NixRebuild.ps1`、`scripts/sh/nixos-wsl-postinstall.sh`、`nix/hosts/wsl/**`は`wsl`を有効にする。Windows host orchestrationを変更するPowerShell fileは同時に`windows`も有効にする。

Windows package manifest変更は`windows`と`package_catalog`を有効にする。`windows/pnpm/packages.json`はWSL Nix rebuildでも消費されるため`wsl`も有効にする。

## Test Strategy

TDDで次の順に実装する。

1. path 1件から期待するplatform/cluster集合を返すtable-driven Python testを失敗させる。
2. 複数pathのunion、未知path、unsafe path、manifest validationを失敗させる。
3. 最小detectorとmanifestを実装して成功させる。
4. workflow path/gate contractをBatsまたは既存Pesterへ追加し、変更前に失敗することを確認する。
5. workflowを更新して契約テストを成功させる。
6. 関連Pester、Bats、Python tests、actionlintを実行する。

代表シナリオとして最低限次を固定する。

| Changed path                                       | Required outputs                                           |
| -------------------------------------------------- | ---------------------------------------------------------- |
| `nix/packages/sets.nix`                            | Linux、Darwin、WSL、Windows、Nix、Chezmoi、package catalog |
| `nix/home/common.nix`                              | Linux、Darwin、WSL、Nix、Chezmoi                           |
| `scripts/sh/install-linux.sh`                      | Linux、contract                                            |
| `scripts/sh/install-macos.sh`                      | Darwin、contract                                           |
| `scripts/sh/nixos-wsl-postinstall.sh`              | WSL、Windows、contract、Nix                                |
| `scripts/powershell/handlers/Handler.NixOSWSL.ps1` | WSL、Windows、contract                                     |
| `chezmoi/dot_config/example`                       | Chezmoi                                                    |
| `docker/hermes-xapi-mcp/Dockerfile`                | Hermesと4platform                                          |

## Safety and Compatibility

- required check名の変更やbranch ruleset更新はこの実装に含めない。
- GitHub Actionsはcommit SHAでpinされたactionだけを追加する。
- secretが利用できないfork PRでもchange detectionとcontract testsが動くようにする。
- manual dispatchは常に全jobを実行できる。
- routingが不明確な共有entrypointは過少実行より過剰実行を選ぶ。
- 全platformのfull acceptanceを削除せず、手動実行で維持する。

## Out of Scope

- branch rulesetの外部変更
- installer本体、Nix package内容、Chezmoi user configurationの挙動変更
- CI実行時間の履歴保存やダッシュボード作成
- runner providerやself-hosted runnerへの移行

## Acceptance Criteria

- Linux、Darwin、WSL、Windowsが独立したrouting outputとしてテストされる。
- shared pathが必要な複数platformへ展開される。
- Nix CIは一般の`scripts/sh/**`や`tests/bash/**`だけでは起動しない。
- Hermes xapi-mcp変更がHermes CIを起動し、Python image contractが実行される。
- Protected Bootstrap E2EとBootstrap Buildは対象platform jobだけを実行し、aggregate contextは常に報告される。
- Chezmoi required check名は変わらず、同一Pester suiteの重複実行がなくなる。
- focused Pester、Bats、Python tests、actionlintが成功する。
