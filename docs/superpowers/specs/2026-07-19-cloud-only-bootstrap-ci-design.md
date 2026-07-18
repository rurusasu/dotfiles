# Cloud-only Cross-platform Bootstrap CI Design

## Goal

Windows、Apple Silicon macOS、NixOS、Ubuntu、Debianのbootstrapを、個人所有マシンや
repository登録済みself-hosted runnerに依存せず、GitHub-hosted Actionsだけで継続的に
検証する。

CIはpull request作成後に人手のEnvironment approvalなしで開始し、利用可能なrunnerがないため
永久にqueuedとなるjobを残さない。`install.cmd`と`./install.sh`が管理する宣言、制御フロー、
冪等性、Linux container runtimeの互換性を、各runnerで実行可能な最も強い検証へ分解する。

## Scope and guarantee boundary

標準GitHub-hosted runnerだけでは、次をpull requestごとに実行できない。

- macOS runner内でnested virtualizationを必要とするDocker Desktop Linux VMを起動すること
- Windows Server runnerへ、Windows 11向けDocker DesktopとWSL2を実機相当で導入すること
- rebootをまたぐWindows feature convergenceを同じjob内で検証すること

したがってCIの保証を、Windows/macOS実機への完全な破壊的convergenceから、次の合成保証へ
変更する。

1. OS別installerの分岐、phase順序、失敗伝播、再実行をstub付きunit/contract testで検証する。
2. nix-darwin、NixOS、System Manager、Home Managerの宣言を対象platform向けに実buildする。
3. Winget、Homebrew cask、Nix package providerのcatalog整合性を静的に検証する。
4. Ubuntu、Debian、NixOSではinstallerを実際に二回適用し、Docker Engine、Compose、
   chezmoi、runtime smokeを検証する。
5. Docker Composeの同一ファイルをLinux runtime E2Eで起動し、OS間で共有するcontainer workloadを
   検証する。

この合成保証は、Windows 11またはmacOS実機でDocker Desktopが起動することを直接証明しない。
実機固有のApple virtualization、WSL2、GUI初回起動、OS再起動、Docker Desktop privileged helperは
ローカルのone-command実行時にinstaller自身のacceptance checkで検出する。ローカル実行結果を
GitHub Actionsの必須条件にはしない。

## Workflow architecture

### Protected Bootstrap E2E

`.github/workflows/ci-bootstrap-e2e-self-hosted.yml`を削除し、後継の
`.github/workflows/ci-bootstrap-e2e-hosted.yml`を追加する。branch protectionで使用する
top-level workflow名`Protected Bootstrap E2E`は維持し、内容をGitHub-hosted contract
workflowへ置き換える。

workflowから次を削除する。

- `runs-on: self-hosted`
- custom label `dotfiles-e2e`
- GitHub Environment `destructive-e2e`
- passwordless sudoを前提とした実機installer実行
- Windows/macOSのDocker Desktop runtime attestation

workflowは次のjobを持つ。

#### Windows Bootstrap Contract

- runner: `windows-2025`
- Pester 5.6.1を固定し、`scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0`を使って、
  `install.cmd` entrypoint、PowerShell handler、acceptance wrapperのunit/contract testsを実行する。
- Winget generated manifestとpackage catalogの一致を検証する。
- WSL、Docker Desktop、NixOS-WSL、chezmoiの外部processは既存wrapper境界でmockし、呼出順序、引数、
  timeout、失敗伝播、二回目実行を検証する。
- 実際のWinget application install、Windows feature変更、WSL distribution登録、Docker Desktop起動は
  行わない。

#### macOS Bootstrap Contract

- runner: `macos-15` ARM64
- Homebrew Bash、UTF-8 locale、GNU coreutilsの`timeout`を用意して、Linuxと同じBats contractを実行可能にする。
- Nixを導入し、`darwinConfigurations.macos.system`を`--impure`付きで実buildする。
- BatsでdispatcherとmacOS installerを実行し、Command Line Tools、Nix、nix-darwin、
  nix-homebrew、Docker Desktop、chezmoiのphase境界をstubで検証する。
- provider catalogから得られるHomebrew cask一覧とnix-darwin宣言の一致を検証する。
- `darwin-rebuild switch`、Homebrew cask install、Docker Desktop起動は行わない。

#### Protected Bootstrap E2E

- runner: `ubuntu-24.04`
- Windows/macOS contract jobの両方を`needs`で要求する。
- どちらかが失敗またはcancelされた場合は成功しない。
- branch protectionで使用する安定したaggregate check名を提供する。

各platform jobは、pull request head SHA、runner image、実行した検証レイヤーをartifactへ記録する。
runtimeを実行していないjobは、空のDocker versionを成功証跡として出力せず、
`runtime=not-applicable-on-github-hosted-runner`を明示する。

### Existing cloud workflows

既存workflowの責務は維持する。

| Workflow                      | Runner                     | Guarantee                                        |
| ----------------------------- | -------------------------- | ------------------------------------------------ |
| `ci-powershell.yml`           | hosted Windows             | lint、Pester、Windows acceptance contract        |
| `ci-consistency.yml`          | hosted Linux               | generated package manifestの差分なし             |
| `ci-nix.yml`                  | hosted Linux               | flake evaluation、package smoke、NixOS-WSL build |
| `ci-bootstrap-build.yml`      | hosted Linux/macOS         | declarative outputの実build                      |
| `ci-bootstrap-e2e-linux.yml`  | hosted Linux               | Ubuntu/Debian/NixOS二回適用とDocker runtime      |
| `ci-bootstrap-e2e-hosted.yml` | hosted Windows/macOS/Linux | OS contractのaggregate required check            |

Windowsは既存`Invoke-Tests.ps1`、macOSは`bats tests/bash`を直接呼び出し、workflow内へ
独自のtest discoveryを実装しない。
ただし、`Protected Bootstrap E2E`はbranch protection用の独立したaggregate checkとして残す。

## Test contracts

### Windows contract requirements

Pester testsは最低限、次を失敗として検出する。

- `install.cmd`が期待するPowerShell entrypointへ引数を転送しない。
- Winget、WSL、Docker、NixOS-WSL、Home Manager、chezmoiの順序が依存関係に反する。
- 外部command failureまたはtimeoutがinstallerの成功へ変換される。
- 導入済みstateの二回目実行で破壊的reinstallが呼ばれる。
- `Test-Environment.ps1`が`docker info`、`docker compose`、`wsl --status`の失敗を無視する。
- generated Winget manifestがcatalogからdriftする。

### macOS contract requirements

BatsとNix buildは最低限、次を失敗として検出する。

- macOS ARM64以外がmacOS installerへdispatchされる。
- `/etc/bashrc`と`/etc/zshrc`のnix-darwin移行処理が既存backupを上書きする。
- 起動中のDocker DesktopをHomebrew cask activation前に停止しない。
- nix-darwin activation後のper-user profileが`PATH`へ追加されない。
- Nix、nix-darwin、nix-homebrew、Home Manager、chezmoiのphase順序が変わる。
- first run failureが成功として扱われる、またはsecond runで不要なbootstrap installerを再実行する。
- macOS package providerまたはHomebrew cask宣言がcatalogからdriftする。
- `darwinConfigurations.macos.system`が対象Apple Silicon configurationとしてbuildできない。

### Runtime requirements

runtime acceptanceはhosted Linuxで実行し、次を必須とする。

- Ubuntu installerのfirst convergenceとsecond idempotent convergence
- Debian systemd-nspawn環境でのfirst/second convergence
- NixOS VMでのactivation、再activation、Docker runtime
- `docker info`、`docker compose version`、runtime smoke container
- 共通Compose fileの`config`、build、up、health check
- chezmoi dry-runと共通CLI command resolution

Windows/macOS contractの成功をLinux runtime成功の代替として扱わず、逆も同様とする。aggregate checkと
既存Linux E2Eの両方をpull requestで確認する。

## Failure handling and observability

- hosted runnerを割り当てられないcustom labelをworkflowに残さない。
- Environment approvalやrepository secretを必須にしない。
- job timeoutをWindows/macOS contractは30分以内、aggregateは5分以内とする。
- test失敗時はJUnitまたはnative test outputを保持する。
- attestation artifactにはpull request head SHAと検証レイヤーを必ず含める。
- network download failureはbounded retry後にjob failureとし、test skipへ変換しない。
- fork pull requestでもread-only tokenだけで同じcontract testsを実行できる構成にする。

## Documentation changes

`docs/ci/self-hosted-bootstrap-runners.md`を削除し、次の文書からself-hosted runner、
`destructive-e2e` Environment、実機attestationをmerge条件とする説明を除く。

- `docs/architecture.md`
- `docs/scripts/powershell/testing.md`
- `docs/superpowers/specs/2026-07-17-cross-platform-bootstrap-design.md`の冒頭へ、本設計が
  self-hosted E2E節を置き換えることを示す参照

READMEのone-command install手順は変更しない。CI保証境界だけを明記し、Windows/macOSでinstaller末尾の
runtime acceptanceが失敗した場合はセットアップ成功と表示されないことを説明する。

## Migration and pull request behavior

PR #429のbranchへworkflow変更を追加し、新しいhead SHAで後継workflowを起動する。古いhead SHAに
残るself-hosted workflow runはGitHub Actions APIから明示的にcancelする。新しいGitHub-hosted jobsと
既存cloud jobsがすべて成功したことを確認してからmergeする。

repositoryのbranch protectionが古いjob名を個別にrequired checkとして登録している場合は、
aggregate `Protected Bootstrap E2E`へ更新する。存在しないself-hosted job名をrequired checkとして
残さない。

## Success criteria

1. repository Actions runner設定が空でも、bootstrap関連の全pull request jobが開始・完了する。
2. active workflowと運用文書に`runs-on: self-hosted`、`dotfiles-e2e`、`destructive-e2e`が残らない。
   過去の判断を記録する日付付きdesign specはこの文字列検査の対象外とする。
3. Windows/macOS contract、declarative builds、Linux destructive runtime E2Eが成功する。
4. Windows/macOS installerの既知の初回・再実行failure pathがunit/contract testsで保護される。
5. PR #429で全required checksが成功し、queued jobを残さずmergeできる。

## Out of scope

- GitHub-hosted runner上でのDocker Desktop起動
- GitHub-hosted Windows runner上でのWSL2/NixOS-WSL runtime
- macOS runnerへのnix-darwin `switch`適用
- 外部CI vendor、MacStadium、Azure専用VM、Docker Offloadの導入
- repository所有者の個人マシンをActions runnerとして登録すること
- Windows/macOS実機テスト結果を手動artifactとしてアップロードする仕組み
