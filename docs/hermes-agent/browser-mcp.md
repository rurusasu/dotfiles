# Hermes Browser MCP

Hermes の browser MCP は host browser ではなく、Compose 内の専用 Google Chrome container と Browser MCP container だけを使う。browser は containerized だが、noVNC を通じて表示できる。
ホスト PC から browser session を見る場合は noVNC を使う。既定 URL は `http://127.0.0.1:6080` で、`HERMES_BROWSER_VIEW_PORT` により host 側 port だけ変更できる。CDP `9222` と Browser MCP `8080` は引き続き host に publish しない。
host 側の Chrome/Chromium/Brave 実行ファイル、host CDP endpoint、host Node/npm/Python は使わない。

## 構成

- `chromium`: 互換性のため service 名は維持しつつ、Xvfb 上の visible Google Chrome を container 内で起動する。CDP は Compose network 内だけに公開し、noVNC viewer だけを `127.0.0.1` に公開する。
- `browser-mcp`: `chrome-devtools-mcp` を `mcp-proxy` 経由で Streamable HTTP MCP として公開する。
- `hermes`: `browser-mcp` service 名で Browser MCP に接続する。

Google Chrome container は `ja_JP.UTF-8` locale と `--lang=ja` で起動し、Chrome UI と日本語入力内容を表示できるようにする。

Hermes から接続する内部 URL は次の固定値にする。

```yaml
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
```

この URL は Compose network 内専用で、host に `8080` や `9222` を publish しない。
サーバー名は Hermes 組み込みの `browser` toolset と衝突しないよう `chrome` にする。

## Browser profile

Google Chrome の profile は専用 data directory に保存する。

```text
${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}
```

既定では Hermes data directory 配下の `.browser` を使う。profile を消すと browser login/session/cache も消えるため、通常の Hermes home や managed profile home とは分けて扱う。
container を更新・再作成しても、この directory は同じ `/data` に bind mount される。既存 profile は削除・初期化せず、Google Chrome で profile を登録すると Chrome が `/data` 内の設定を更新する。更新後の profile を古い Chromium へ戻す downgrade は保証しない。

## 起動

最初に dotfiles の config apply を実行し、Hermes install handler に root/profile の `config.yaml` を更新させる。
この手順で root と managed profile の `mcp_servers.chrome` に `http://browser-mcp:8080/mcp` が書き込まれる。

```powershell
dotf chezmoi
```

その後、Browser MCP image と Google Chrome image を更新してから Hermes を起動する。

```powershell
task hermes:pull
task hermes:up
```

`dotf chezmoi` が使えない環境では、同じ install handler config-apply path を実行してから `task hermes:pull` / `task hermes:up` に進む。`task hermes:up` は Hermes、Google Chrome、Browser MCP を同じ Compose project/network で起動する。Hermes の `config.yaml` は install handler が管理し、既存の unrelated MCP server は残したまま `browser` block を上記 URL に置き換える。
