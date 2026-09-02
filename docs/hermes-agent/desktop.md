# Hermes Desktop

## 構成

macOS の `./install.sh --with-hermes` は、次の2つを別々に管理します。

- ホスト: 公式 `NousResearch/hermes-agent` flake の `desktop` 出力を Nix/Home
  Manager で導入し、`hermes-desktop` コマンドを提供する。
- Docker: `docker/hermes-service/compose.yml` の Hermes Agent、gateway、Web
  Dashboard、Browser/MCP サービスを起動する。

Desktop の GUI を Agent コンテナに入れる必要はありません。コンテナは GUI を
提供するイメージではなく、Agent の実行環境と Dashboard/API を提供します。

## CLI の実行

Hermes Desktop は GUI フロントエンドであり、macOS ホストのシェルで CLI を
実行する機能はありません。また、この構成では公式の CLI は Docker コンテナ内に
だけ存在します。そのため `WithHermes` プロファイルでは、ホストの
`hermes-docker` が既存の `hermes` サービスへコマンドを転送します。

リポジトリからは、次のように実行できます。引数はコンテナ内の CLI へそのまま
渡されます。

```bash
task hermes:cli -- -p personal-ops config check
task hermes:cli -- profile list
```

リポジトリ外から直接実行する場合は、Compose ファイルを明示します。

```bash
HERMES_COMPOSE_FILE="$HOME/.dotfiles/docker/hermes-service/compose.yml" \
  hermes-docker -p personal-ops chat
```

このアダプターはサービスを自動起動・停止しません。先に `task hermes:up` を
実行し、Docker Desktop と Hermes コンテナが起動していることを確認してください。
対話端末ではTTYを維持し、パイプやCIではTTY割り当てを無効にするため、チャットと
設定検証の両方を同じコマンドで扱えます。

公式ドキュメントでも Desktop App、CLI/TUI、Web Dashboard は同じ Agent に接続
する別のフロントエンドとして説明されています。Desktop は `hermes-desktop`
で起動し、Web Dashboard は `hermes dashboard` が提供します。

## 接続先

Compose は Dashboard をホストの次の loopback ポートへ公開します。

```text
http://127.0.0.1:9119
```

Desktop の Remote Gateway には、この URL を指定します。dotfiles の `WithHermes`
プロファイルを適用済みなら、保存済みの Desktop remote 接続と gateway health を
検証する `hermes-desktop-docker` を使って起動できます。初回だけ Desktop の
Settings > Gateway でこの URL を登録し、システムブラウザで認証してください。
Docker gateway は先に `task hermes:up` で起動してください。別のマシンから接続する場合は loopback 公開のままでは到達できないため、
認証、TLS、ファイアウォールを含む別の公開設計が必要です。

## 状態と秘密情報

API key、OAuth token、profile、session、memory、モデル、Docker のデータは
`~/.hermes` などの runtime path に保存します。Nix 式へ秘密値を記述したり、Nix
store に runtime state を生成したりしないでください。

## 手動確認

```bash
task hermes:desktop
docker compose -f docker/hermes-service/compose.yml ps
curl -fsS http://127.0.0.1:8642/health
```

`9119` は Desktop の Remote Gateway/Dashboard 接続先、`8642` は gateway 内部 API
の health 確認用です。`hermes-desktop-docker` は Desktop の app-owned
`connections.json` に保存された remote 接続を検証します。OAuth 接続の token は
Desktop の native token store、token 接続の envelope は Desktop/OS Keychain の
管理境界に残り、launcher はいずれも読み出しません。秘密情報は Git、Nix store、
通常ログ、プロセス引数へコピーされません。
接続が未設定、gateway が停止中の場合は、Desktop を起動せず終了します。

公式の Desktop 操作と remote backend の設定は、[Hermes Desktop
documentation](https://hermes-agent.nousresearch.com/docs/user-guide/desktop) と
[Web Dashboard の remote 接続ガイド](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard)
を参照してください。
