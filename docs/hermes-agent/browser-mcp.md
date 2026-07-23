# Hermes Browser MCP

Hermes の browser MCP は host browser ではなく、Compose 内の専用 Google Chrome container と Browser MCP container だけを使う。browser は containerized だが、noVNC を通じて表示できる。
ホスト PC から browser session を見る場合は noVNC を使う。既定 URL は `http://127.0.0.1:6080` で、`HERMES_BROWSER_VIEW_PORT` により host 側 port だけ変更できる。CDP `9222` と Browser MCP `8080` は引き続き host に publish しない。
host 側の Chrome/Chromium/Brave 実行ファイル、host CDP endpoint、host Node/npm/Python は使わない。

## 構成

- `chromium`: 互換性のため service 名は維持しつつ、Xvfb 上の visible Google Chrome を container 内で起動する。CDP は Compose network 内だけに公開し、noVNC viewer だけを `127.0.0.1` に公開する。
- `browser-mcp`: `chrome-devtools-mcp` を `mcp-proxy` 経由で Streamable HTTP MCP として公開する。
- `hermes`: `browser-mcp` service 名で Browser MCP に接続する。

Google Chrome container は `ja_JP.UTF-8` locale と `--lang=ja` で起動し、Chrome UI と日本語入力内容を表示できるようにする。
noVNC viewer は通常の `Cmd/Ctrl+C`、`Cmd/Ctrl+X`、`Cmd/Ctrl+V` を Google Chrome 側のショートカットへ変換し、プレーンテキストの clipboard をホストと双方向に同期する。

Hermes から接続する内部 URL は次の固定値にする。

```yaml
agent:
  disabled_toolsets:
    - browser
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
```

この URL は Compose network 内専用で、host に `8080` や `9222` を publish しない。
サーバー名は Hermes 組み込みの `browser` toolset と衝突しないよう `chrome` にする。
全 managed profile は `agent.disabled_toolsets` で組み込みの `browser` toolset を
無効化し、別の local browser session を選択できないようにする。

## Distribution source contract

root distribution と `docker/hermes-agent/bootstrap-manifest.yaml` に宣言された
全 profile は、source repository の `config.yaml` で上記の
`mcp_servers.chrome` と built-in `browser` の無効化を所有する。各 distribution
manifest の `distribution_owned` は `config.yaml` を明示的に含める。他の MCP
server は `chrome` と共存できる。

Bootstrap は全 distribution を stage した後、shared repository の同期や local
transaction の開始前に、配布所有権、built-in `browser` の無効化、URL、timeout
を検証する。設定の注入、merge、修復は行わない。新しい profile を manifest に
追加すると、同じ検証へ自動的に含まれる。manifest 外で手動作成した profile は
管理対象外のままにする。

Hermes 組み込みの `browser_*` tool は、noVNC が表示する Chrome とは別の local
browser session を起動するため、managed profile では無効である。agent は
`mcp_servers.chrome` から discover された tool を使う。

## Browser profile

Google Chrome の profile は専用 data directory に保存する。

```text
${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}
```

既定では Hermes data directory 配下の `.browser` を使う。profile を消すと browser login/session/cache も消えるため、通常の Hermes home や managed profile home とは分けて扱う。
container を更新・再作成しても、この directory は同じ `/data` に bind mount される。既存 profile は削除・初期化せず、Google Chrome で profile を登録すると Chrome が `/data` 内の設定を更新する。更新後の profile を古い Chromium へ戻す downgrade は保証しない。

## 起動

`mcp_servers.chrome` は root/profile の source distribution が所有する。Bootstrap
はその declarative config を適用するが、one-shot `hermes-bootstrap` service は
`chromium` と `browser-mcp` に依存しない。Browser services も bootstrap の依存先
ではない。Bootstrap 成功後の `compose up` で通常の stack は起動され、browser
lifecycle task だけを後から独立して実行することもできる。

```text
task hermes:browser:pull
task hermes:browser:restart
```

Browser が lifelog を参照する場合も canonical path は
`/opt/data/shared/lifelog` である。migration-only の
`/opt/data/core/lifelog` を runtime 設定へ追加しない。

## Runtime verification

各 profile home を明示して、同じ Chrome MCP tool set を discover できることを
確認する。

```text
docker exec -e HERMES_HOME=/opt/data hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/rick hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/hoffman hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/risarisa hermes hermes mcp test chrome
docker exec -e HERMES_HOME=/opt/data/profiles/nancy hermes hermes mcp test chrome
```

全コマンドで接続が成功し、`navigate_page` と `take_snapshot` を含む同じ tool set
が表示されることを確認する。`hermes tools list --platform slack` では built-in
`browser` が disabled と表示されることも確認する。host noVNC は
`http://127.0.0.1:6080/` で開く。
