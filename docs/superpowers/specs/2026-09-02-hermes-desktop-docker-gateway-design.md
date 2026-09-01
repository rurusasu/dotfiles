# Hermes Desktop の Docker gateway 接続 IaC 設計

## 背景

macOS 上の Hermes Desktop は、通常起動するとホスト上にローカル backend を起動する。現在の Hermes 設定にある `browser-mcp` と `xapi-mcp` は Docker Compose 内部 DNS 名のため、ホスト backend から名前解決できず MCP が unreachable になる。

一方、Docker の Hermes gateway は Dashboard/Remote Gateway 用の `http://127.0.0.1:9119` をホスト loopback に公開している。`8642` は Desktop の Remote Gateway 接続先ではなく、コンテナ API の health 用ポートである。

## 決定事項

### 1. Desktop の app-owned 接続状態は管理しない

Hermes Desktop の `connections.json` と暗号化された token は Desktop 自身の設定・Keychain 境界に属する。chezmoi で symlink 化したり、Nix 式で内容を生成したりしない。

### 2. Nix 管理の起動ラッパーを提供する

`WithHermes` プロファイルに `hermes-desktop-docker` を追加する。ラッパーは以下を実行する。

1. `http://127.0.0.1:9119/api/health` に到達できることを確認する。
2. Hermes Desktop の app-owned `connections.json` に、同 URL の primary remote 接続と暗号化 token があることを確認する。
3. upstream の `hermes-desktop` を `exec` する。Desktop が保存 token を Keychain から読み込み、API/WS の認証を担当する。

Token はラッパーが読み取らず、標準出力・標準エラー・プロセス引数・Git 管理対象・Nix store に出さない。接続設定がない、registry が不正、gateway が停止中の場合は、既存の Desktop や Docker を変更せず、復旧方法を示して終了する。

### 3. Docker 公開ポートと Compose は変更しない

MCP サービスをホストへ追加公開しない。Docker 内の `browser-mcp`、`xapi-mcp` と Hermes gateway の既存ネットワークをそのまま利用する。ラッパーは Docker の起動・停止も行わず、ライフサイクルは既存の `hermes:up` / `hermes:down` に委譲する。

## 対象範囲

- Darwin の `WithHermes` パッケージセット
- shell adapter とその Bats 契約テスト
- Hermes Taskfile の Desktop 起動エントリポイント
- `docs/hermes-agent/desktop.md` と関連設計文書

Windows、Linux、Hermes Desktop 本体、Docker 認証方式、1Password の item/key 作成は対象外とする。

## テスト方針

- ラッパー単体テストで、保存済み primary remote 接続の検証、token 非露出、registry 欠損/不正、gateway 不到達を検証する。
- パッケージカタログと Darwin profile の評価で、`WithHermes` のみラッパーが導入されることを検証する。
- Taskfile 契約テストで、Desktop 起動がラッパーを経由し、Compose の MCP 公開ポートを増やしていないことを検証する。
- 実機では token の値を表示せず、9119 の `/api/health`、Docker gateway の状態、ラッパーから起動された Desktop の remote 接続を確認する。

## 失敗時の境界

ラッパーの失敗は Desktop の起動前に発生する。既存の Desktop 接続状態、Docker コンテナ、runtime secret は変更しない。bootstrap の再実行は別操作として `task hermes:bootstrap` または `task hermes:up` から行う。
