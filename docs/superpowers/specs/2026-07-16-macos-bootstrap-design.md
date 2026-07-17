# macOS Bootstrap Design

## Goal

Apple Silicon Mac の新規環境で、リポジトリを clone した後に `./install.sh`
を一度実行するだけで、Homebrew、Docker Desktop、Nix、Home Manager、
chezmoi、Hermes Docker Compose stack までセットアップする。

Windows と Linux では既存の Docker Compose 構成を維持し、macOS でも同じ
`docker/hermes-agent/compose.yml` を利用して実行環境の互換性を優先する。

## Supported environment

- Apple Silicon Mac
- macOS 26 以降
- 管理者権限を持つ対話ユーザー
- 個人利用の Docker Desktop
- リポジトリをローカル clone 済み

Intel Mac、Linux、Windows からの `install.sh` 実行は対象外とし、明確な案内を
表示して終了する。Windows の入口は引き続き `install.cmd` とする。

## Entry points

### `install.sh`

リポジトリ直下の薄いプラットフォーム dispatcher とする。

- macOS かつ arm64 であることを検証する。
- 実体の `scripts/sh/install-macos.sh` を実行する。
- 対応外 OS では、利用すべき既存インストーラを表示して非ゼロ終了する。

### `scripts/sh/install-macos.sh`

macOS セットアップ全体を順序制御する。各フェーズは独立した関数として実装し、
既に適用済みの状態では何もしない冪等な処理にする。

## Setup flow

### 1. Preflight

- `uname -s` が `Darwin`、`uname -m` が `arm64` であることを確認する。
- `xcode-select -p` で Command Line Tools を確認する。
- 未導入の場合は `xcode-select --install` を起動し、完了後の再実行を案内して
  終了する。GUI インストール完了を無期限に待たない。
- リポジトリルート、`flake.nix`、`chezmoi/`、
  `docker/hermes-agent/compose.yml` の存在を確認する。

### 2. Homebrew

- `brew` が見つからない場合のみ、Homebrew 公式インストーラを実行する。
- インストール直後は `/opt/homebrew/bin/brew shellenv` を現在のプロセスへ
  適用する。
- Home Manager の macOS セッション PATH に `/opt/homebrew/bin` と
  `/opt/homebrew/sbin` を追加し、以後の zsh セッションでも利用できるようにする。
- `brew update` は自動実行しない。初回セットアップに不要な更新時間と差分を
  増やさないためである。

### 3. Docker Desktop

- `/Applications/Docker.app` がない場合のみ
  `brew install --cask docker-desktop` を実行する。
- Docker Desktop の内部 installer を
  `--accept-license --user="$USER"` 付きで実行し、初回 GUI 起動時の
  ライセンス確認と privileged configuration を事前適用する。
- このフェーズでは `sudo` による管理者認証が発生し得る。
- Apple Silicon 上で amd64 Chromium image を実行するため、Rosetta 2 が
  未導入なら `softwareupdate --install-rosetta --agree-to-license` を実行する。
- `docker desktop start` を実行し、`docker info` が成功するまで上限付きで
  polling する。
- Docker Desktop が時間内に起動しない場合はログ確認コマンドを表示して停止する。

Docker Desktop の利用条件は実行前に README とスクリプト出力で案内する。
本設計の対象は個人利用であり、企業向け自動ライセンス判断は行わない。

### 4. Nix

- `nix` が見つからない場合のみ、Nix 公式 multi-user daemon installer を
  `--daemon` で実行する。
- インストール後は
  `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` を読み込み、
  同一プロセス内で Nix を利用可能にする。
- `~/.config/nix/nix.conf` に `nix-command` と `flakes` を重複なく有効化する。
  既存設定は削除しない。

### 5. Repository link

- `~/.dotfiles` が存在しない場合は、実行中リポジトリへの symbolic link を作る。
- 既に同じリポジトリを指す link なら何もしない。
- 別の file、directory、または link が存在する場合は、削除せず
  `~/.dotfiles.backup.<timestamp>` へ移動してから link を作る。
- backup path をログに表示し、操作を可逆にする。

### 6. Home Manager

- `aarch64-darwin` configuration を `--impure` 付きで build する。
  `nix/home/common.nix` が `USER` と `HOME` を `builtins.getEnv` から取得するため、
  pure evaluation は使用しない。
- `nix build --no-link --print-out-paths
  .#homeConfigurations.aarch64-darwin.activationPackage --impure` の結果にある
  `activate` を実行する。
- 既存 Home Manager generation がある場合も、同じ activation を再適用できる。
- activation 後に Home Manager profile の PATH を現在のプロセスへ反映する。

### 7. Chezmoi

- Home Manager により導入された `chezmoi` を使用する。
- clone 済みの `chezmoi/` を source として `chezmoi init` する。
- `chezmoi apply --force` で macOS 用テンプレートと deploy scripts を反映する。
- 1Password 連携が利用できない deploy script は、各 script の既存方針に従い
  bounded / non-fatal に扱う。chezmoi 本体の失敗はセットアップ失敗とする。

### 8. Docker Compose build and startup

- `docker compose -f docker/hermes-agent/compose.yml config` を最初に実行する。
- Chromium service に `platform: linux/amd64` を明示し、Apple Silicon 上でも
  Google Chrome amd64 image を Rosetta 経由で再現可能にする。
- 次の順で実行する。

```bash
docker compose -f docker/hermes-agent/compose.yml build --pull
docker compose -f docker/hermes-agent/compose.yml up -d --force-recreate --wait
```

- Compose project 名、service 名、network、volume、healthcheck、port mapping は
  既存 `compose.yml` を Single Source of Truth とする。
- `chromium` と `browser-mcp` が healthy、`hermes` が running であることを
  `docker compose ps` と `docker inspect` で確認する。
- `127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}`、
  `127.0.0.1:${HERMES_API_PORT:-8642}`、
  `127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}` の到達性を上限付きで確認する。
- 失敗時は `docker compose ps` と直近ログを表示して非ゼロ終了する。

## Idempotency and failure handling

- インストール済み Homebrew、Docker Desktop、Nix は再インストールしない。
- Home Manager、chezmoi、Compose は再実行して最新宣言へ収束させる。
- 破壊的な `docker system prune`、volume 削除、既存 dotfiles の削除は行わない。
- 外部 process の待機にはすべて timeout を設ける。
- 各フェーズを明示的にログ出力し、失敗したコマンドと再実行方法を表示する。
- 途中失敗後も `./install.sh` を再実行して続行できる。

## Testing

### Bash tests

新しい Bats tests では PATH 上の stub command と一時 HOME を使い、実マシンを
変更せず以下を検証する。

- dispatcher が macOS arm64 のみを受け付ける。
- Homebrew、Docker Desktop、Nix が存在する場合は再インストールしない。
- 未導入時は各 installer が正しい引数で呼ばれる。
- Nix activation build に `aarch64-darwin` と `--impure` が含まれる。
- chezmoi が clone 済み source を使用して apply される。
- Compose が config、build、up、health verification の順で呼ばれる。
- 既存 `~/.dotfiles` が削除されず backup される。
- timeout と command failure が非ゼロ終了になる。

### Static and repository checks

- `bash -n install.sh scripts/sh/install-macos.sh`
- `bats tests/bash`
- `docker compose -f docker/hermes-agent/compose.yml config`
- `nix flake check --no-build`
- `git diff --check`

### Runtime acceptance

対象 Mac 上で `./install.sh` を実行し、以下を確認する。

1. `brew --version`
2. `nix --version`
3. `home-manager --version`
4. `chezmoi --version`
5. `docker version`
6. `docker compose version`
7. Home Manager 管理ツールの代表例として `gh --version` と `nvim --version`
8. `docker compose ... ps` で Hermes stack が running / healthy
9. API、dashboard、noVNC の localhost endpoint が応答

## Documentation

- README のクイックスタートを OS 別に分ける。
- macOS では `git clone`、`cd dotfiles`、`./install.sh` の3行を主経路にする。
- 管理者認証、Docker Desktop 利用条件、初回 build に時間がかかること、
  再実行可能であることを明記する。
- Windows の `install.cmd` と Linux/NixOS の既存手順は維持する。

## Out of scope

- Apple `container` runtime
- Colima、Podman、OrbStack への自動 fallback
- Intel Mac
- Docker Desktop の企業ライセンス判定
- Docker Hub や private registry への自動 login
- Hermes profile や Slack/X OAuth の対話セットアップ
