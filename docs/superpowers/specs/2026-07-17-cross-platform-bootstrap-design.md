# Cross-platform One-command Bootstrap Design

> **CI update (2026-07-19):** The Windows/macOS self-hosted E2E sections are superseded by [Cloud-only Cross-platform Bootstrap CI Design](./2026-07-19-cloud-only-bootstrap-ci-design.md). The installer and declarative-layer design remains current.

## Goal

Windows、Apple Silicon macOS、NixOS、Ubuntu、Debianで、clone済みの本リポジトリから
OSごとに1つのコマンドを実行すると、パッケージマネージャー、共通アプリケーション、
ユーザー設定、DockerとDocker Compose、対象サービスまでが宣言された状態へ収束する
仕組みを作る。

同じコマンドを再実行しても壊れないことを必須とし、単なる設定評価だけでなく、専用の
実行環境へ実際に適用する破壊的E2Eで完成状態を検証する。

## Design decisions

### Declarative layers

OS間の共通部分をHome Managerから外すのではなく、次の三層に分ける。

1. `nix/packages/sets.nix`: アプリケーションとCLIのSingle Source of Truth
2. Home Manager: macOS/Linux共通のユーザーパッケージとdotfiles連携
3. OS system layer:
   - Windows: Winget + PowerShell handlers
   - macOS: nix-darwin + nix-homebrew + Home Manager module
   - NixOS: NixOS module + Home Manager module
   - Ubuntu/Debian: System Manager + Home Manager module

Home Managerは共通ユーザー層として維持する。Docker daemon、Homebrew cask、systemd、
Windows管理者設定のようなシステム状態をHome Managerへ押し込まない。

### Supported tiers

| OS                  | Architecture   | Support          | One command                               | System layer                    |
| ------------------- | -------------- | ---------------- | ----------------------------------------- | ------------------------------- |
| Windows 11          | x86_64         | Full             | `install.cmd`                             | Winget + PowerShell + WSL/NixOS |
| macOS 26+           | aarch64        | Full             | `./install.sh`                            | nix-darwin + nix-homebrew       |
| NixOS               | x86_64/aarch64 | Full             | `./install.sh`                            | NixOS modules                   |
| Ubuntu with systemd | x86_64/aarch64 | Full             | `./install.sh`                            | System Manager                  |
| Debian with systemd | x86_64/aarch64 | Full             | `./install.sh`                            | System Manager                  |
| Other Linux         | x86_64/aarch64 | User-only opt-in | `DOTFILES_ALLOW_USER_ONLY=1 ./install.sh` | standalone Home Manager         |

未検証ディストリビューションで部分的なセットアップを成功扱いにしない。その他Linuxは
明示的なopt-in時だけHome Managerとchezmoiを適用し、Docker/systemdを含むFull support
ではないことを終了時に表示する。

Intel macOS、Windows on ARM、systemdを使用しない汎用Linuxは今回のFull support対象外とする。

## Flake architecture

`flake.nix`から次の出力を提供する。

```text
flake.nix
├── nixosConfigurations
│   ├── nixos              # existing NixOS-WSL
│   └── linux              # native NixOS
├── darwinConfigurations
│   └── macos              # nix-darwin + nix-homebrew + Home Manager
├── systemConfigs
│   ├── ubuntu             # System Manager + Home Manager
│   └── debian             # System Manager + Home Manager
├── homeConfigurations
│   ├── x86_64-linux       # unsupported-Linux fallback
│   └── aarch64-linux
├── packages
│   ├── winget-export
│   └── package-support-report
├── apps
│   ├── darwin-rebuild     # pinned nix-darwin input wrapper
│   └── system-manager     # pinned System Manager input wrapper
└── checks
    ├── package-provider-coverage
    ├── darwin-configuration
    ├── linux-system-configurations
    └── home-configurations
```

`system-manager`、`nix-darwin`、`nix-homebrew`をflake inputとしてpinし、すべての
Home Manager/Nix modulesが同じ`nixpkgs` revisionへ追従する。

ユーザー名、home directory、リポジトリpathはbootstrapが環境変数
`DOTFILES_USER`、`DOTFILES_HOME`、`DOTFILES_ROOT`として渡す。これらを必要とする
build/switchには`--impure`を使用する。値が空、相対path、rootユーザーとの不整合である
場合は評価前に停止する。

## Cross-platform application catalog

### Catalog model

既存の`nix/packages/sets.nix`をSSOTとして維持するが、`windowsOnly`へ混在している
クロスプラットフォームアプリをprovider付きcatalogへ移す。

概念上、各entryは次の情報を持つ。

```nix
{
  name = "docker";
  category = "system";
  providers = {
    windows.winget = "Docker.DockerDesktop";
    darwin.cask = "docker-desktop";
    linux.systemModule = "docker";
  };
  unsupported = { };
}
```

CLIやNixで共通提供できるアプリは既存の`pkg = pkgs.<name>`を利用する。GUIや
OS-native componentだけ`darwin.cask`、`windows.winget`、`linux.systemModule`を
持つ。provider名は実装上attrsetへ正規化してもよいが、以下のinvariantを変えない。

### Catalog invariants

- WingetまたはMicrosoft Storeへ出力される全entryは、macOSとLinuxについて
  provider、または理由付き`unsupported`を持つ。
- `windowsOnly`にはPowerToys、VCRedist、Visual Studio Build Tools、Windows Terminal、
  WSLのような真のWindows固有componentだけを残す。
- Docker、VS Code、Chrome、1Password、Bun、Zig、dprint、hadolintなど、他OSに
  providerが存在するものを`windowsOnly`へ置かない。
- 同じアプリをHome ManagerとHomebrew caskの両方で重複インストールしない。
- platform availabilityはNix derivationの`meta.platforms`だけに暗黙依存せず、catalogの
  support metadataでも検証する。
- GUI版とCLI版が異なる製品の場合は別entryとする。例えばCodex CLIとCodex desktopを
  同一entryとして扱わない。

`package-support-report`はWindows、macOS、Linuxごとのproviderとunsupported reasonを
JSONで出力する。CIはproviderも理由もないcellが1つでもあれば失敗する。

## One-command entrypoints

### Shared POSIX dispatcher

リポジトリ直下の`install.sh`をmacOS専用dispatcherからPOSIX共通dispatcherへ変更する。

1. `uname`、`/etc/os-release`、NixOS marker、architectureを検出する。
2. `DOTFILES_PLATFORM` overrideはテスト専用時だけ許可する。
3. 対象に応じて次へ`exec`する。
   - macOS: `scripts/sh/install-macos.sh`
   - NixOS: `scripts/sh/install-nixos.sh`
   - Ubuntu/Debian: `scripts/sh/install-linux.sh`
   - その他Linux: opt-inを確認して`scripts/sh/install-home-manager.sh`
4. Windows-like shellでは`install.cmd`を案内して非ゼロ終了する。

全installerは`set -euo pipefail`、phase名付きlog、bounded wait、再実行可能なstate detectionを
共通libraryから利用する。外部downloadはHTTPS、可能なものはchecksumまたはpin済みflake
inputで検証する。

### Windows

入口は既存の`install.cmd`を維持する。

- Phase 1でWinget manifestからユーザーアプリをインストールする。
- 管理者PhaseでWSL、Docker Desktop、OS設定を適用する。
- NixOS-WSLとHome Managerをswitchする。
- chezmoiとDocker Compose servicesを適用する。
- generated Winget/npm/pnpm manifestはcatalogからのみ生成する。
- installer最後に共通acceptance commandを実行する。

既存PowerShell handler architectureを維持し、provider catalogとの整合性検証だけを追加する。

### macOS

`./install.sh`は次の順で収束させる。

1. Apple Silicon、macOS version、管理者権限、Command Line Toolsをpreflightする。
2. Command Line Toolsがない場合はインストールを開始し、完了をbounded pollingして同じ実行を
   継続する。timeout時だけ再実行方法を表示する。
3. Nix daemonがなければ公式multi-user installerで導入する。
4. Nix profileを現在のprocessへ読み込む。
5. 実行checkoutを`~/.dotfiles`へ安全にlinkする。異なる既存pathはtimestamp付きbackupへ移す。
6. `nix run .#darwin-rebuild -- switch --flake .#macos --impure`を実行する。
7. nix-darwinがHome Manager moduleを同じgenerationでactivationする。
8. nix-homebrewがHomebrew本体を管理し、nix-darwinの`homebrew.casks`がDocker Desktopなどの
   caskを収束させる。
9. Docker Desktopのlicense acceptanceとprivileged setupを行い、engineを起動して
   `docker info`をbounded pollingする。
10. chezmoiを適用し、Compose servicesをbuild/up/health-checkする。
11. 共通acceptance commandを実行する。

Homebrewをshell scriptから直接`brew install --cask`しない。Docker Desktop DMG fallbackも
通常経路から外し、nix-homebrew/nix-darwinの宣言を唯一の通常providerとする。upstream cask
障害に備えたbreak-glass手順はdocumentationに残してよいが、自動fallbackで宣言状態を
迂回しない。

### NixOS

NixOSでは既存Nixを使用し、`nixos-rebuild switch --flake .#<detected-config> --impure`を実行する。

- Home Manager moduleを同じsystem generationでactivationする。
- Docker daemon、Compose plugin、ユーザーのdocker group membershipをNixOS moduleで管理する。
- switch後にchezmoiとCompose servicesを収束させる。
- WSLではWindows Docker Desktop連携とnative Docker daemonを同時に有効化せず、既存host optionで
  どちらか一方を選ぶ。

### Ubuntu and Debian

Nixがない場合は公式multi-user installerを導入し、次を実行する。

```bash
nix run .#system-manager -- switch --flake .#ubuntu --sudo --impure
```

Debianでは`#debian`を使用する。`apps.system-manager`はflake lock済みinputを参照し、
unpinned URLをruntimeで取得しない。

System Managerが次を管理する。

- system-wide Nix settings
- Docker Engine、Compose、Buildx
- `/etc/docker/daemon.json`
- Docker systemd service/socket
- 対象ユーザーとdocker group membership
- Home Manager user configuration

group membership変更後は、新しいlogin sessionが必要な場合がある。installerは現在sessionで
`sg docker`相当を利用してacceptanceを完了し、終了時に再loginが必要であることを表示する。

## Convergence and failure handling

- installerはphaseごとに`check`, `apply`, `verify`の境界を持つ。
- package manager、Nix、Homebrew、Dockerを導入済みなら再インストールしない。
- declarative switch、chezmoi apply、Compose upは毎回実行し、最新宣言へ収束させる。
- timeoutを持たないpollingやinteractive promptをCI modeで残さない。
- failure時はphase名、失敗command、関連service status、再実行commandを表示する。
- `docker system prune`、volume削除、ユーザーhomeの削除は行わない。
- 既存設定をbackupする場合はpathをsummaryへ出力する。
- installerが成功を返すのは、そのOSのFull acceptanceがすべて通った場合だけとする。

## Acceptance command

OS別installerの末尾とE2E workflowは、共通の`verify-environment` entrypointを実行する。
read-only checkを基本とし、`--runtime`でDocker smoke workloadを実行する。

最低限、次を検証する。

1. package manager and declarative layer:
   - Windows: `winget`, handler completion marker
   - macOS: `nix`, `darwin-rebuild`, `brew`, Home Manager generation
   - Linux: `nix`, System Manager/NixOS generation, Home Manager generation
2. common CLI: `git`, `gh`, `chezmoi`, `rg`, `fd`, `jq`, `nvim`, `node`, `python`, `go`,
   `rustup`, `docker`, `docker compose`
3. catalog support reportに対象OSの未解決entryがないこと
4. chezmoi source/stateがcheckoutと一致し、`chezmoi apply --dry-run`でunexpected diffがないこと
5. Docker daemonへ対象ユーザーで接続できること
6. `docker run --rm hello-world`相当のruntime smoke
7. `docker compose config`、build、up、service health、localhost endpoints

secretや外部OAuthを必要とするserviceは、secret未設定時に明示的な`not-configured`状態を返せる。
ただしDocker、共通CLI、declarative generation、chezmoiはskip不可とする。

## Test strategy

### Unit tests

#### POSIX/Bats

- dispatcherのmacOS/NixOS/Ubuntu/Debian/unsupported Linux routing
- installer phase順序と引数
- Nix未導入・導入済みの両経路
- nix-darwin/System Manager/NixOS switch command
- user/home/root validation
- timeout、download failure、switch failure、Docker readiness failure
- 既存`~/.dotfiles`のbackupと冪等性
- second runがinstallerを再導入せずdeclarative switchへ進むこと

#### Windows/Pester

- `install.cmd`からuser/admin phase完了までのorchestration
- catalogから生成したWinget manifestの適用
- Docker Desktop、WSL、NixOS、Home Manager、chezmoi、Composeの順序
- second runとrecovery path
- acceptance command failureのpropagation

すべての新規behaviorは、失敗するtestを先に追加してから最小実装を行う。

### Flake and catalog checks

- `nix flake check --no-build`
- 全supported architectureのHome Manager evaluation
- `darwinConfigurations.macos.system`のbuild
- NixOS toplevel/VMのbuild
- Ubuntu/Debian `systemConfigs`のbuild
- Winget/npm/pnpm generated filesのdiff
- package-provider coverage reportの未解決cell検査
- nix-darwinのHomebrew cask listとcatalogのDarwin providersの一致
- System Manager packages/modulesとcatalog Linux providersの一致

### Destructive Linux E2E

GitHub-hosted ephemeral Ubuntu runnerへ`./install.sh`を実際に適用する。

1. checkout直後のrunnerでNix/System Manager/Docker/Home Managerを導入する。
2. `verify-environment --runtime`を実行する。
3. `./install.sh`を二回目実行する。
4. generation、Docker、chezmoi、Composeが引き続きhealthyであることを確認する。

Debianはprivileged systemd-nspawn VM/container、または同等の破棄可能なsystemd環境を
Ubuntu runner上に作り、同じ二回実行を行う。systemdなしの単純Docker containerによる
疑似testで代替しない。

NixOSはNixOS VM testでswitch、Home Manager、Docker runtime、二回目activationを検証する。

### Destructive Windows E2E

Docker DesktopとWSL2を実行可能な専用self-hosted Windows 11 runnerを使用する。

- labels: `self-hosted`, `Windows`, `X64`, `dotfiles-e2e`
- `install.cmd`を実行し、必要なelevationを非対話で許可する専用test accountを使用する。
- Winget、Docker Desktop、WSL/NixOS、Home Manager、chezmoi、Composeを実適用する。
- acceptanceを実行後、`install.cmd`を再実行して冪等性を検証する。

### Destructive macOS E2E

GitHub-hosted arm64 macOS runnerはnested virtualization非対応でDocker Desktop engineを
起動できないため、専用のphysical Apple Silicon Macをself-hosted runnerとして使用する。

- labels: `self-hosted`, `macOS`, `ARM64`, `dotfiles-e2e`
- Command Line Tools以外を事前条件にしないclean-bootstrap profileを定期的に使用する。
- `./install.sh`でNix、nix-darwin、nix-homebrew、Homebrew casks、Docker Desktop、
  Home Manager、chezmoi、Composeを実適用する。
- `verify-environment --runtime`を実行する。
- `./install.sh`を二回目実行し、再インストールがなく、同じ宣言へ収束することを確認する。
- Docker Desktop licenseは個人利用を前提とし、runner ownerが事前に利用条件を承認する。

永続runnerの通常PR testでは既存generationからの収束と冪等性を検証する。Nix未導入状態からの
clean bootstrapは、専用volume/hostを初期化できるscheduledまたはmanual jobでも検証する。

### Self-hosted runner security and gating

このリポジトリがpublicであることを前提に、破壊的self-hosted jobsは次を必須にする。

- fork PRでは実行しない。
- 同一repository内branchだけを対象にする。
- GitHub Environment `destructive-e2e`のowner approval後だけ開始する。
- owner以外がworkflow_dispatchで任意SHAを指定できないようactor/refを検証する。
- runnerは本リポジトリ専用account/hostとし、個人tokenや他repository secretsを置かない。
- `concurrency`で同一OSの同時実行を禁止する。
- job timeoutとinstaller phase timeoutを設定する。
- workflowはcommit SHA、generation、provider report、acceptance resultをartifactとして保存する。

PRをmerge可能にするには、hosted unit/build checksに加え、Ubuntu destructive E2E、Windows
destructive E2E、macOS destructive E2Eが同一head SHAで成功していなければならない。

## CI workflow layout

```text
ci-bootstrap-unit.yml
├── bats
├── pester
└── catalog-provider-coverage

ci-bootstrap-build.yml
├── nixos-build
├── system-manager-ubuntu-build
├── system-manager-debian-build
├── home-manager-linux-build
└── nix-darwin-build

ci-bootstrap-e2e-linux.yml
├── ubuntu-destructive
├── debian-systemd-destructive
└── nixos-vm

ci-bootstrap-e2e-self-hosted.yml
├── windows-destructive
└── macos-destructive
```

既存workflowを無条件に増やさず、重複するci-nix、ci-winget、ci-devcontainer checkは上記へ
統合または呼び出し可能workflow化する。required check nameは移行中も安定させる。

## Documentation

READMEのQuick Startを次の三入口へ統一する。

```powershell
install.cmd
```

```bash
./install.sh  # macOS
```

```bash
./install.sh  # NixOS / Ubuntu / Debian
```

各OSについて、管理者認証、初回所要時間、Docker license、再実行可能性、supported tier、
failure時のdiagnostic commandを記載する。

次の運用資料も追加または更新する。

- package provider追加手順
- self-hosted macOS/Windows runner登録と専用label設定
- `destructive-e2e` Environment保護設定
- runnerのclean-bootstrap/reset手順
- providerが存在しないOSにunsupported reasonを追加する基準

## Delivery phases

一つのPRで無制限に変更しないよう、依存順に実装する。ただし最終merge条件は全phaseの
acceptanceが揃うことである。

1. catalog schema、provider report、flake inputs/outputs
2. macOS nix-darwin/nix-homebrew migrationとtests
3. Ubuntu/Debian System Manager bootstrapとtests
4. NixOS/Windows entrypointの共通acceptance統合
5. destructive E2E workflowsとrunner documentation
6. README/architecture migration、全matrix verification

実装計画では各phaseをtest-firstの小さなcommit単位へ分解する。

## Out of scope

- Apple `container` runtime、Colima、Podman、OrbStackへの自動fallback
- Intel macOSとWindows on ARMのFull support
- Fedora/Arch等でのexperimental System Manager `allowAnyDistro`
- Docker Desktop企業ライセンスの自動判定
- 自動OAuth login、1Password vault内容、個人secretのCI投入
- self-hosted runner hardwareの購入・OS再インストール自動化

## References

- [Home Manager installation and module modes](https://nix-community.github.io/home-manager/installation.html)
- [nix-darwin manual](https://nix-darwin.github.io/nix-darwin/manual/)
- [nix-homebrew](https://github.com/zhaofengli/nix-homebrew)
- [System Manager documentation](https://system-manager.net/main/)
- [System Manager Docker example](https://system-manager.net/main/examples/docker/)
- [System Manager Home Manager example](https://system-manager.net/main/examples/home-manager/)
- [GitHub-hosted runner limitations](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub self-hosted runner requirements](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [GitHub self-hosted runner security warning](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)

## Acceptance criteria

完了には次をすべて満たす必要がある。

1. Windowsで`install.cmd`一回からFull acceptanceが成功する。
2. Apple Silicon macOSで`./install.sh`一回からFull acceptanceが成功する。
3. NixOS、Ubuntu、Debianで`./install.sh`一回からFull acceptanceが成功する。
4. 各Full support OSで同じcommandの二回目も成功する。
5. Windows package entryのmacOS/Linux providerまたはunsupported reasonが100%埋まる。
6. hosted build/evaluation matrixが全て成功する。
7. Ubuntu、Debian、NixOS destructive E2Eが成功する。
8. 専用self-hosted Windows/macOS destructive E2Eが同一head SHAで成功する。
9. Docker runtimeとCompose health checkを含む共通acceptanceが成功する。
10. generated manifests、flake lock、documentationが実装と一致する。
