# Hermes Desktop

## 構成

macOS の `./install.sh --with-hermes` は、次の2つを別々に管理します。

- ホスト: 公式 Homebrew Cask `hermes-desktop` を nix-homebrew で宣言し、
  `/Applications/Hermes.app` に公式セットアップアプリを導入する。セットアップは
  Hermes の管理runtime、CLI、packaged Desktopをユーザー領域へ導入する。
- Docker: `docker/hermes-service/compose.yml` の Hermes Agent、gateway、Web
  Dashboard、Browser/MCP サービスを起動する。

Desktop の GUI を Agent コンテナに入れる必要はありません。コンテナは GUI を
提供するイメージではなく、Agent の実行環境と Dashboard/API を提供します。

## 公式セットアップ

`./install.sh --with-hermes` はcaskの配置だけでは成功扱いにしません。
`task hermes:desktop:install` が公式セットアップを起動し、次のすべてが揃うまで
待機します。

- `~/.local/bin/hermes`
- `~/.hermes/hermes-agent/.hermes-bootstrap-complete`
- `~/.hermes/hermes-agent/apps/desktop/release/.../Hermes.app/Contents/MacOS/Hermes`

セットアップ起動時は、呼び出し元だけに有効な
`GIT_CONFIG_COUNT`、`GIT_CONFIG_KEY_*`、`GIT_CONFIG_VALUE_*`を継承しません。
これにより、欠けたcommand-scope設定でセットアップ内部の`git clone`が毎回失敗する
状態を防ぎます。完了済みの場合はセットアップを再起動せず、成果物を再検証します。

## CLI の実行

公式セットアップはmacOSホストに`~/.local/bin/hermes`を導入します。これはDesktop
自身が使うローカルruntimeを操作します。Docker上の既存Hermes Agentを明示的に
操作する場合は、`WithHermes`プロファイルの`hermes-docker`を使用します。

リポジトリからは、次のように実行できます。引数はコンテナ内の CLI へそのまま
渡されます。

```bash
task hermes:cli -- -p personal-ops config check
task hermes:cli -- profile list
```

Compose は `GATEWAY_MULTIPLEX_PROFILES=true` で、root gateway の1プロセスから
すべてのProfileを提供します。対象Profileの状態確認は次のように実行できます。

```bash
PROFILE=personal-ops task hermes:profile:status
PROFILE=personal-ops task hermes:profile:up
PROFILE=personal-ops task hermes:profile:restart
PROFILE=personal-ops task hermes:profile:down
PROFILE=career-ops task hermes:profile:status
PROFILE=dev-lab task hermes:profile:status
```

`hermes:profile:status` だけが指定Profileの状態を照会します。
`hermes:profile:up` はroot multiplexerを起動してから指定Profileの状態を表示し、
`hermes:profile:restart` もroot multiplexer全体を再起動してから状態を表示します。
`hermes:profile:down` はHermes Compose stackを停止するため、ほかのProfileも同時に
停止します。multiplexモードでは `-p <profile> gateway start|run|stop|restart` を
直接実行しません。

既存のProfile名付きtaskも、同じroot lifecycleへのaliasとして利用できます。

```bash
task hermes:rick:up
task hermes:rick:restart
task hermes:rick:down
```

`hoffman`、`risarisa`、`nancy` にも同じ `up`、`restart`、`down` aliasがあります。
Profile名はTaskfile側でshell-safeにargv化されます。CLIの既定Composeファイルは既存の
`docker/hermes-service/compose.yml`に固定され、別ファイルを使う場合だけ
`HERMES_COMPOSE_FILE`で明示指定します。

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
する別のフロントエンドとして説明されています。Desktop は
`hermes-desktop-docker` が macOS の `open /Applications/Hermes.app` を通して起動し、Web
Dashboard は `hermes dashboard` が提供します。

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
curl -fsS http://127.0.0.1:9119/api/health
```

`9119` は Desktop が接続する `hermes serve` / Dashboard backend であり、起動確認も
公開エンドポイント `/api/health` に対して行います。`8642` は gateway の
OpenAI-compatible API で、Desktop backend の起動確認には使用しません。
`hermes-desktop-docker` は Desktop の app-owned
`connections.json` に保存された remote 接続を検証します。OAuth 接続の token は
Desktop の native token store、token 接続の envelope は Desktop/OS Keychain の
管理境界に残り、launcher はいずれも読み出しません。秘密情報は Git、Nix store、
通常ログ、プロセス引数へコピーされません。
接続が未設定、gateway が停止中の場合は、Desktop を起動せず終了します。

公式の Desktop 操作と remote backend の設定は、[Hermes Desktop
documentation](https://hermes-agent.nousresearch.com/docs/user-guide/desktop) と
[Web Dashboard の remote 接続ガイド](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard)
を参照してください。
