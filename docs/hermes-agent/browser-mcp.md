# Hermes Browser MCP

Hermes の browser MCP は host browser ではなく、Compose 内の専用 Chromium container と Browser MCP container だけを使う。
host 側の Chrome/Chromium/Brave 実行ファイル、host CDP endpoint、host Node/npm/Python は使わない。

## 構成

- `chromium`: headless Chromium を container 内で起動し、CDP を Compose network 内だけに公開する。
- `browser-mcp`: `chrome-devtools-mcp` を `mcp-proxy` 経由で Streamable HTTP MCP として公開する。
- `hermes`: `browser-mcp` service 名で Browser MCP に接続する。

Hermes から接続する内部 URL は次の固定値にする。

```yaml
mcp_servers:
  browser:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
```

この URL は Compose network 内専用で、host に `8080` や `9222` を publish しない。

## Browser profile

Chromium の profile は専用 data directory に保存する。

```text
${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}
```

既定では Hermes data directory 配下の `.browser` を使う。profile を消すと browser login/session/cache も消えるため、通常の Hermes home や managed profile home とは分けて扱う。

## 起動

最初に dotfiles の config apply を実行し、Hermes install handler に root/profile の `config.yaml` を更新させる。
この手順で root と managed profile の `mcp_servers.browser` に `http://browser-mcp:8080/mcp` が書き込まれる。

```powershell
dotf chezmoi
```

その後、Browser MCP image と Chromium image を更新してから Hermes を起動する。

```powershell
task hermes:pull
task hermes:up
```

`dotf chezmoi` が使えない環境では、同じ install handler config-apply path を実行してから `task hermes:pull` / `task hermes:up` に進む。`task hermes:up` は Hermes、Chromium、Browser MCP を同じ Compose project/network で起動する。Hermes の `config.yaml` は install handler が管理し、既存の unrelated MCP server は残したまま `browser` block を上記 URL に置き換える。
