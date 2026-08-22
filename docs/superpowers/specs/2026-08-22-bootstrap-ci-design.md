# Bootstrap CI 統合設計

## 目的

bootstrap 関連の GitHub Actions workflow を `Bootstrap CI` に統一し、Linux、Darwin、WSL、Windows の検証を同一 workflow から並列に起動する。workflow 名と job 名から対象プラットフォームと検証層を判別できるようにし、現在の検証内容と変更ルーティングを維持する。

## 対象範囲

次の workflow を統合対象とする。

- `ci-bootstrap-build.yml`: Linux/Darwin の declarative build
- `ci-bootstrap-e2e-linux.yml`: Ubuntu、Debian、NixOS の Linux bootstrap E2E
- `ci-nixos-wsl.yml`: Windows runner 上の NixOS-WSL E2E
- `ci-bootstrap-e2e-hosted.yml`: Windows bootstrap contract と Darwin bootstrap contract

`ci-winget.yml` は Windows の package/environment smoke test であり、bootstrap の OS convergence 契約とは責務が異なるため、今回の統合対象外とする。

## 命名規則

workflow ファイルと表示名を次に統一する。

- ファイル: `.github/workflows/ci-bootstrap.yml`
- workflow 名: `Bootstrap CI`
- platform job 表示名: `Bootstrap / Linux / ...`、`Bootstrap / Darwin / ...`、`Bootstrap / WSL`、`Bootstrap / Windows`
- 集約 job 表示名: `Bootstrap / Complete`

検証層は次の語彙に限定する。

- `Build`: Nix の declarative output をビルドする検証
- `Contract`: 設定・スクリプト・生成物の契約を検証するテスト
- `E2E`: 実際の bootstrap、install、switch、idempotent convergence を実行する検証

検証層を独立 workflow 名にせず、platform job の表示名または step 名で表現する。OS ごとに runner、shell、セットアップ、artifact が異なるため、単一の巨大な matrix step ではなく、共通の `changes` job と platform 別 job 群を使う。

## 構成

共通の `changes` job が `detect-ci-changes` を一度だけ実行し、`linux`、`darwin`、`wsl`、`windows` の outputs を公開する。統合後の bootstrap 判定には `ci/bootstrap-path-routing.json` を使い、各 platform job は `changes` の成功後、対象 output が `true` の場合だけ起動し、相互には依存しない。

workflow が path trigger によって起動しても、全 platform job を無条件には実行しない。既存の `scripts/python/detect_ci_changes.py` と `ci/path-routing.json` による platform 判定をそのまま利用し、各 job の `if` で実行対象を絞る。例えば Windows 専用 package の変更では Windows job だけが起動し、Darwin 専用 package の変更では Darwin job だけが起動する。共有 package 定義や共通 installer の変更では、routing が返す複数 platform の job が起動する。`workflow_dispatch` の手動実行では、既存の `run-all` 契約に従い全 platform を実行する。

この platform 単位の絞り込みは Linux と WSL にも同じように適用する。Linux 専用 path の変更では Linux の build/E2E job だけを起動し、WSL 専用 path の変更では WSL job だけを起動する。Windows runner を共有する WSL と Windows も一つの `windows` output にまとめず、`wsl` と `windows` の routing output を別々に評価する。WSL のホスト実装ファイルは bootstrap routing では WSL に属するものとして扱い、Windows bootstrap contract を起動しない。

platform ごとの検証は次のとおりとする。

- Linux: declarative build、Ubuntu destructive convergence、Debian systemd convergence、NixOS VM build
- Darwin: declarative build、POSIX/Hammerspoon contract、provider coverage
- WSL: Windows runner の WSL2 準備と isolated NixOS-WSL switch
- Windows: chezmoi、AutoHotkey、Pester による Windows bootstrap contract

Linux の既存 3 E2E job は同じ workflow 内で個別 job として保持し、相互に並列実行できるようにする。これにより workflow を統合しても、Linux の検証を一つの長い直列 job に変えない。

全 platform job の完了後、`Bootstrap / Complete` が `always()` で起動する。`changes` が成功し、各 platform job の結果が `success` または routing による `skipped` である場合だけ成功とする。失敗・キャンセル・異常結果は失敗として扱う。

## 変更ルーティングとトリガー

新 workflow は既存 bootstrap workflow の path trigger を統合する。共通 detector/action、routing 定義、workflow 自体の変更は全 platform output を有効化する既存契約を利用する。

既存の全 CI 用 `ci/path-routing.json` は他 workflow の契約を壊さないため維持する。bootstrap 専用の `ci/bootstrap-path-routing.json` を追加し、旧 bootstrap workflow の trigger 範囲を platform 単位に整理して記述する。`detect-ci-changes` と composite action は任意の manifest path を受け取れるようにし、通常 CI は既存 manifest、`Bootstrap CI` は bootstrap manifest を使う。新 workflow の workflow 固有ルールは bootstrap manifest 側に置き、削除する旧 workflow への参照を残さない。

path trigger は workflow を起動するための候補範囲であり、実行 platform を決める source of truth ではない。実行 platform は bootstrap manifest の routing output と job-level `if` で決める。この境界を保つことで、Windows package 変更時に workflow の `changes` job と `Bootstrap / Windows` だけが実行され、Darwin package 変更時に `Bootstrap / Darwin` だけが実行される。Linux package、WSL package、各 platform の専用 installer/host path も同じ規則で対象 job だけを起動する。routing の既存ルールが共有扱いにしている `nix/packages/**` などは、意図した cross-platform package set として全対象を実行する。

トリガーは `workflow_dispatch`、`main` への push、`main` 向け pull request とする。pull request の fork から secrets や Windows/WSL の privileged runtime を使う既存制約は維持し、該当 job を安全に skip する。

## 互換性と整理

新 workflow への移行後、統合済みの 4 workflow ファイルは削除する。job の表示名は新命名に統一するため、既存 branch protection が旧 job 名を required check として参照している場合は、リポジトリ側の required check 設定を新名へ更新する必要がある。

artifact 名には platform と検証層を含め、同一 run 内で衝突しないようにする。既存の attestation 内容とテストコマンドは原則変更せず、workflow の配置・needs・job 名だけを整理する。

## 検証方針

1. YAML の構文と workflow の job/needs/if の整合性を静的に検証する。
2. routing の既存 Bats/Python テストを実行し、platform output の契約を確認する。
3. bootstrap manifest に対して Linux、Darwin、WSL、Windows の各専用 path と共有 path の routing テストを確認し、対象外 platform が `false` になることを検証する。既存 manifest の WSL/Windows 連動契約も通常 CI 用として維持されることを確認する。
4. 新 workflow が対象 path と旧 workflow の実行対象を引き継いでいることを focused script で確認する。
5. 変更差分を確認し、旧 workflow の参照、重複した trigger、artifact 名の衝突、fork PR での権限逸脱がないことを確認する。
6. hosted GitHub Actions では 4 platform の job が共通 `changes` 後に変更対象だけ並列起動し、`Bootstrap / Complete` が `success` / `skipped` を正しく集約することを確認する。

## 非対象

- `ci-winget.yml` の package catalog/environment smoke test の統合
- platform-specific bootstrap script 自体の挙動変更
- Nix、PowerShell、chezmoi のテスト内容や依存バージョンの変更
- GitHub repository の branch protection / required checks 設定変更
