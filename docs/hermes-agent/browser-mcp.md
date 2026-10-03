# Hermes Browser MCP

Hermes の browser MCP は host browser ではなく、Compose 内の専用 browser sidecar を使う。Hermes本体はNix管理のnative serviceで、sidecarは独立して動作する。
ホスト PC から browser session を見る場合は noVNC を使う。既定 URL は `http://127.0.0.1:6080` で、`HERMES_BROWSER_VIEW_PORT` により host 側 port だけ変更できる。CDP `9222` と Browser MCP `8080` は引き続き host に publish しない。
host 側の Chrome/Chromium/Brave 実行ファイル、host CDP endpoint、host Node/npm/Python は使わない。

## 構成

- `chromium`: 互換性のため service 名は維持しつつ、Xvfb 上の visible browser を container 内で起動する。AMD64 では Google Chrome、ARM64 では Debian Chromium を使う。CDP は Compose network 内だけに公開し、noVNC viewer だけを `127.0.0.1` に公開する。
- `browser-mcp`: `chrome-devtools-mcp` を `mcp-proxy` 経由で Streamable HTTP MCP として公開する。MCP要求は120秒で打ち切り、ページ単位の操作はDevToolsのpage IDでルーティングする。Chrome DevTools MCPは1.6.0、MCP proxyは6.5.5に固定する。
- native Hermes: `127.0.0.1:8765` の Browser MCP endpoint に接続する。

Browser container は `ja_JP.UTF-8` locale と `--lang=ja` で起動し、Chrome/Chromium UI と日本語入力内容を表示できるようにする。長寿命の専用ブラウザでバックグラウンドページが凍結・破棄されると、CDPの `Runtime.enable` や `Accessibility.getFullAXTree` が停止してMCP全体のsnapshotがタイムアウトするため、背景Rendererの抑制とTabDiscardingを無効化する。
noVNC viewer は通常の `Cmd/Ctrl+C`、`Cmd/Ctrl+X`、`Cmd/Ctrl+V` を browser 側のショートカットへ変換し、プレーンテキストの clipboard をホストと双方向に同期する。

### Host clipboard の条件と fallback

remote → host copy は `navigator.clipboard.writeText` を優先し、API が無い場合や
書込みが拒否された場合は textarea を使う `document.execCommand("copy")` に
fallback する。`documentCopyInProgress` は、この document copy が同期的に発火する
copy イベントを remote copy として再処理しないための状態である。`finally` で
textarea と状態を解放し、noVNC に focus を戻す。

Clipboard API は secure context を必要とする。既定の loopback HTTP 接続と、
非 loopback 名の HTTP 接続は同じ条件ではない。ブラウザによって権限と user
activation の条件も異なるため、fallback を維持する。
[Clipboard API の条件](https://developer.mozilla.org/en-US/docs/Web/API/Clipboard_API)
を参照。

2026-10-01 に macOS の Google Chrome for Testing 151.0.7922.71 と、実行中の
AMD64 sidecar の Google Chrome 151.0.7922.173 / noVNC で、配布する module と
trusted keyboard 入力を使って次を確認した。host clipboard は OS から、remote
paste 結果は専用テストタブの textarea から読戻した。

| host viewer の条件                                                           | 実測結果                                                                       |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `http://127.0.0.1:6080`、通常の権限                                          | secure context / API あり。日本語の remote copy が `writeText` で成功          |
| 同じ loopback 接続、検証用 browser context で clipboard 権限を denied に設定 | `writeText` は `NotAllowedError`。document copy は成功し、日本語を host に同期 |
| 同じ endpoint を非 loopback 名の HTTP で開く                                 | secure context ではなく API が無い。document copy が成功                       |

権限拒否時の copy では、document copy が発火した trusted copy イベントは
キャンセルされず、remote への Ctrl+C は利用者の操作につき一度だけ送られた。
次の copy も成功し、再入防止の状態が解放されることを確認した。host → remote
paste は ASCII、日本語、Clipboard API の権限拒否中も確認した。ただし権限拒否中の
日本語 paste は最初の一度で空の結果となり、通常権限と拒否権限での再試行は成功した。
原因は特定できていないため、paste の安定性まで保証する結果ではない。Firefox、Safari、
ARM64 sidecar はこの実測の対象外であり、同じ結果を保証するものではない。

再確認時は専用タブの textarea で `Ctrl+A` → `Cmd/Ctrl+C` を行い、host の別の
入力欄に貼り付けて内容を確認する。逆方向は host で文字列をコピーし、remote
textarea に `Cmd/Ctrl+V` で貼り付ける。権限拒否後も同じ操作と、異なる文字列の
二度目の copy を確認する。両方の copy 手段をブラウザが拒否した場合は自動同期
できないため、noVNC の clipboard panel に受信したテキストから手動でコピーする。

`docker/hermes-browser/tests/test_runtime_contract.sh` は同じ clipboard module の
イベント処理を Node で実行し、API 不在・拒否・成功、document copy の再入、例外
後の状態解放、ASCII/UTF-8 paste と二重 paste 防止を検証する。このテストは実 UI
と OS clipboard の読戻しの代わりにはならない。

Hermes から接続する内部 URL は次の固定値にする。

```yaml
agent:
  disabled_toolsets:
    - browser
mcp_servers:
  chrome:
    url: http://127.0.0.1:8765/mcp
    connect_timeout: 120
```

この loopback URL は host 上の native Hermes から接続する。MCP は `127.0.0.1:8765` のみに公開し、CDP `9222` は host に公開しない。
サーバー名は Hermes 組み込みの `browser` toolset と衝突しないよう `chrome` にする。
全 managed profile は `agent.disabled_toolsets` で組み込みの `browser` toolset を
無効化し、別の local browser session を選択できないようにする。固定した Hermes
runtime では `web_search` を `browser` toolset から除外して `web` toolset にだけ
所属させるため、この設定で Web 検索は無効にならない。

## Distribution source contract

root distribution と `nix/home/hermes-agent/manifest.yaml` に宣言された
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

Chrome/Chromium の profile は専用 data directory に保存する。

```text
${HERMES_BROWSER_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.browser}
```

既定では Hermes data directory 配下の `.browser` を使う。profile を消すと browser login/session/cache も消えるため、通常の Hermes home や managed profile home とは分けて扱う。
container を更新・再作成しても、この directory は同じ `/data` に bind mount される。既存 profile は削除・初期化せず、実行中の Chrome/Chromium が `/data` 内の設定を更新する。AMD64 と ARM64 の間でブラウザを切り替えた後に、profile を古いブラウザへ戻す downgrade は保証しない。

## 起動

`mcp_servers.chrome` は root/profile の source distribution が所有する。Nix側の
profile sync はその宣言設定を反映する。Browser sidecar はHermes本体とは独立して
起動・更新する。

```text
task hermes:browser:pull
task hermes:browser:restart
```

Browser が lifelog を参照する場合も canonical path は
`${HERMES_HOME}/shared/lifelog` である。migration-only の
`${HERMES_HOME}/core/lifelog` を runtime 設定へ追加しない。

## Runtime verification

各 profile home を明示して、同じ Chrome MCP tool set を discover できることを
確認する。

```text
hermes mcp test chrome
hermes -p rick mcp test chrome
hermes -p hoffman mcp test chrome
hermes -p risarisa mcp test chrome
hermes -p nancy mcp test chrome
```

全コマンドで接続が成功し、`navigate_page` と `take_snapshot` を含む同じ tool set
が表示されることを確認する。`hermes tools list --platform slack` では built-in
`browser` が disabled、`web` が enabled と表示されることも確認する。host noVNC は
`http://127.0.0.1:6080/` で開く。

長時間のブラウザ処理は、Chrome操作を逐次化し、一覧1ページまたは詳細2〜5件を
1バッチとして扱う。各バッチの完了時にページ番号・候補ID・URLをcheckpointへ
記録し、詳細ページを閉じる。`take_snapshot`、`click`、`navigate_page` のいずれかが
タイムアウトした場合は、そのバッチを未完了として停止し、1回だけ限定的な再読込を
試す。再発時は同じページへ操作を重ねず、browser servicesを再起動してcheckpoint
から再開する。レビューや候補判定の並列化は、Chromeからの証拠取得が終わった後に
行う。
