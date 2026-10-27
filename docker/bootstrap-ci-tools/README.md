# Bootstrap CI tools image

`ci-nix.yml` の `nix`、`linux-build`、
`wsl-prebuild` は、このイメージで検査・ビルドを実行します。
`bash-test` もこのイメージで Bash テストを一度だけ実行します。
Nix、Bash、Bats、chezmoi、go-task、Git / Git LFS、Python 3.14、Ruby、Node.js 24、PowerShell、
PSScriptAnalyzer の最新安定版、statix、jq、tar、xz を事前導入します。
`nix fmt` の formatter と検証対象のパッケージは、引き続き checkout した flake から選択します。

## 更新と再利用

`ci-nix.yml` 内の `ci-tools` ジョブが Dockerfile、`nix.conf`、`check.sh`、`profile.sh` の
内容ハッシュをタグにして GHCR の既存イメージを探します。
存在しない場合だけビルド・実行検証・公開を行い、利用側へ digest を返します。
通常の dotfiles 変更や `flake.lock` 更新ではツールイメージを再ビルドしません。
ツールを更新するときは Dockerfile の base image digest / `NIXPKGS_REV` を更新します。

公開先は `ghcr.io/<owner>/<repository>/bootstrap-ci-tools` です。
公開権限はイメージ準備ジョブだけが持ち、利用側は `packages: read` で取得します。
リポジトリ内の PR、main push、手動実行は未公開の定義をビルドできます。
fork PR は公開済みイメージを読み取り専用で使用します。
fork がツール定義自体を変更した場合は、maintainer がリポジトリ内のブランチで
その定義をビルドしてから検証します。未公開定義を別のイメージに置き換えることはありません。

## 実行環境の境界

イメージは GitHub Actions の JavaScript actions に必要な共有ライブラリを持つ
Debian ベースです。公式 Nix イメージから登録済み store をコピーし、
各検査ジョブでは Nix の導入処理を実行しません。
ローカル store へ書き込む CI のため root で実行します。
Nix sandbox は有効で、Nix のビルドを行う job container は `--privileged` を指定します。
固定の Nix 設定と binary cache は `nix.conf` に置き、CI workflow では
`NIX_CONFIG` 環境変数を設定しません。GitHub token は
`scripts/sh/configure-bootstrap-ci-nix.sh` が実行ユーザーの専用設定ファイルへ
権限 600 で保存します。token をイメージに含めたり、ログへ出力したりしません。
WSL でも同じスクリプトで root / nixos の両方を設定し、builder の並列数制限を維持します。

`nix` ジョブは statix の検査を行い、format と全 flake checks は `check` に集約します。
アプリを含む OS 構成は Linux / Darwin の各 build job で検証します。
事前の `nix eval` や `nix flake check --no-build` は重ねません。
Linux / Darwin / WSL / Windows の実行条件は、共有 checks の分類と独立しています。
Windows manifest の変更では共有 checks と Windows installer を実行し、Unix の build は起動しません。
OS 固有 host の変更は該当 OS、共有 Nix module / flake input の変更は依存する各 OS を選択します。
Ubuntu / Debian の個別構成 build と E2E は実行せず、NixOS VM の検証は維持します。
WSL は本番構成を一度 build し、E2E で使う cache を生成します。
ホストの SDK 削除や Docker イメージの一括削除は行いません。

Bash テストは同じ workflow の Linux `bash-test` job に集約し、
`scripts/sh/run-bash-tests.sh` を実行します。ローカルの `task test:bash` も同じ runner を使います。
Darwin build job には Bash テスト用のインストール処理を置きません。
OS 分岐の契約は stub で検証し、実 OS が必要な動作は別の E2E が担当します。
push / PR では軽量な変更検出を必ず実行し、必要な job だけ起動します。

以下はホスト固有の処理を持つため、ホストで実行します。

- NixOS E2E: KVM を使う VM テストを実行する。
- Darwin / Windows / WSL E2E: 対象 OS のネイティブ環境を検証する。

## Nix 成果物の再利用

`.github/actions/cache-nix` が GitHub Actions cache を復元・保存します。追加アカウントや secret は不要です。
OS・architecture・Nix version・job・flake.lock のハッシュで分離し、同じ inputs、次に同じ実行環境の順で復元します。
成功した main の commit だけが保存し、PR は main の cache を読み取ります。

- 全ジョブで公式 `actions/cache` の file binary cache を使い、store DB は保存しません。
  `cache.nixos.org` にある成果物は metadata ごと除外し、公開 substituter から取得します。
  実現済みの全出力を調べるため、macOS の torch などのビルド用依存も保存対象です。
  Darwin は activation 直後に private 出力を GC root で保持し、checks 中の GC による削除を防ぎます。
- 圧縮は Nix の zstd を GC root と PATH で固定します。Homebrew cleanup 後も同じツールを使います。
- 保存上限は Darwin 2 GiB、Linux / WSL は各 768 MiB、checks は 512 MiB です。上限超過時は警告し、前世代を維持します。
  世代の保持は [GitHub の自動削除](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#usage-limits-and-eviction-policy)に任せます。
  この repository は他 workflow と合計 10 GB を共有し、未使用 7 日または容量超過時の LRU で古い cache が削除されます。
- WSL への同一 run の artifact: 完全な cache の hardlink 複製から、`cache.nixos.org` に依存一式がある
  NAR payload だけを除きます。metadata は残し、Windows 側で署名付きの公開依存を先に取得してから取り込みます。
  公開 cache の判定は並列実行し、問い合わせ失敗時は未確認の payload を省きません。

初回や GitHub 側の容量制限で cache が削除された場合は通常の build に戻ります。
warm run の時間と cache / artifact のサイズは hosted Actions のログで確認します。

## ローカル検証

リポジトリのルートから実行します。

```bash
docker buildx build --platform linux/amd64 --load \
  --tag dotfiles-bootstrap-ci-tools:local docker/bootstrap-ci-tools
docker run --rm --platform linux/amd64 --privileged \
  dotfiles-bootstrap-ci-tools:local \
  bash /usr/local/libexec/check-bootstrap-ci-tools.sh --sandbox
```

イメージのビルド時にも `check.sh` を実行します。
CI の公開前検証では、加えて sandbox 内の小さな derivation をビルドします。

Apple Silicon の Docker Desktop で amd64 をエミュレーションすると、Nix の
seccomp フィルタで失敗する場合があります。その場合のローカル検証に限り、
`docker run` に `--env 'NIX_CONFIG=filter-syscalls = false'` を追加します。
Nix sandbox は有効なままです。GitHub の amd64 runner ではこの例外を設定しません。
