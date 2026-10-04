# Bootstrap CI tools image

`ci-bootstrap.yml` の `nix`、`linux-build`、
`wsl-prebuild` は、このイメージで検査・ビルドを実行します。
`bash-test` もこのイメージで Bash テストを一度だけ実行します。
Nix、Bash、Bats、chezmoi、go-task、Git / Git LFS、Python 3.14、Ruby、Node.js 24、PowerShell、
PSScriptAnalyzer 1.22.0、statix、jq、tar、xz を事前導入します。
`nix fmt` の formatter と検証対象のパッケージは、引き続き checkout した flake から選択します。

## 更新と再利用

`ci-bootstrap.yml` 内の `ci-tools` ジョブが Dockerfile、`nix.conf`、`check.sh`、`profile.sh` の
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

`nix` ジョブは lint と format の確認だけを行い、失敗をそのままジョブへ反映します。
アプリを含む OS 構成と設定テストは Linux / Darwin の各 build job に集約します。
事前の `nix eval` や `nix flake check --no-build` は重ねません。
Linux build は Linux または Nix の変更で実行します。
Ubuntu / Debian の個別構成 build と E2E は実行せず、NixOS VM の検証は維持します。
WSL は通常構成と Hermes 有効構成をそれぞれ build し、E2E で使う cache を生成します。
ホストの SDK 削除や Docker イメージの一括削除は行いません。

Bash テストは同じ workflow の Linux `bash-test` job に集約し、
`scripts/sh/run-bash-tests.sh` を実行します。ローカルの `task test:bash` も同じ runner を使います。
Darwin build job には Bash テスト用のインストール処理を置きません。
OS 分岐の契約は stub で検証し、実 OS が必要な動作は別の E2E が担当します。
push / PR では軽量な変更検出を必ず実行し、必要な job だけ起動します。

以下はホスト固有の処理を持つため、ホストで実行します。

- NixOS E2E: KVM を使う VM テストを実行する。
- Darwin / Windows / WSL E2E: 対象 OS のネイティブ環境を検証する。

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
