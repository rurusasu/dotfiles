# Hermes Desktop

## 構成

macOS の `./install.sh --with-hermes` は、次の2つを別々に管理します。

- ホスト: 公式 `NousResearch/hermes-agent` flake の `desktop` 出力を Nix/Home
  Manager で導入し、`hermes-desktop` コマンドを提供する。
- Docker: `docker/hermes-service/compose.yml` の Hermes Agent、gateway、Web
  Dashboard、Browser/MCP サービスを起動する。

Desktop の GUI を Agent コンテナに入れる必要はありません。コンテナは GUI を
提供するイメージではなく、Agent の実行環境と Dashboard/API を提供します。

公式ドキュメントでも Desktop App、CLI/TUI、Web Dashboard は同じ Agent に接続
する別のフロントエンドとして説明されています。Desktop は `hermes-desktop`
で起動し、Web Dashboard は `hermes dashboard` が提供します。

## 接続先

Compose は Dashboard をホストの次の loopback ポートへ公開します。

```text
http://127.0.0.1:9119
```

Desktop の remote backend 設定でこの URL を指定し、Dashboard の認証を通過して
ください。別のマシンから接続する場合は loopback 公開のままでは到達できないため、
認証、TLS、ファイアウォールを含む別の公開設計が必要です。

## 状態と秘密情報

API key、OAuth token、profile、session、memory、モデル、Docker のデータは
`~/.hermes` などの runtime path に保存します。Nix 式へ秘密値を記述したり、Nix
store に runtime state を生成したりしないでください。

## 手動確認

```bash
hermes-desktop
docker compose -f docker/hermes-service/compose.yml ps
curl -fsS http://127.0.0.1:8642/health
```

公式の Desktop 操作と remote backend の設定は、[Hermes Desktop
documentation](https://hermes-agent.nousresearch.com/docs/user-guide/desktop) と
[Web Dashboard の remote 接続ガイド](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard)
を参照してください。
