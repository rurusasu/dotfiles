# Hermes Browser MCP

Codex と root Hermes は、Home Manager が管理する native `mcp-chrome` service に
HTTP で接続する。service は Nix の `mcp-proxy` を使い、1つの
`chrome-devtools-mcp` process と専用 browser profile を共有する。

## 構成

[`nix/modules/ai_agents/mcp.nix`](../../nix/modules/ai_agents/mcp.nix) の共通 `chrome`
定義は `http://127.0.0.1:8765/mcp` を使う。native service が保持する stdio child
には次の引数を設定する。

```text
chrome-devtools-mcp
  --headless
  --executable-path=<Nix-managed Chrome/Chromium>
  --user-data-dir=<root Hermes home>/.browser
  --no-usage-statistics
```

[`mcp-packages.nix`](../../nix/modules/ai_agents/mcp-packages.nix) は
`mcp-servers` flake input の `chrome-devtools-mcp` package をそのまま使う。
取得元は `github:natsukium/mcp-servers-nix` で、dotfiles 側に別の version や
npm package 定義を持たない。`nix flake update mcp-servers` で provider の固定 revision
を更新し、通常の Nix 反映を行う。MCP の起動時に npm install を実行しない。

ブラウザは headless で起動するため、Linux/WSL の display や WSLg を必要としない。
`mcp-chrome` は Linux の systemd user service、macOS の launchd agent として動く。
HTTP は loopback のみに公開する。Docker と noVNC は使わない。

## Browser profile

Browser profile は root Hermes home の `.browser` に保存する。既定値は
`~/.hermes/.browser` で、全 client が同じ native MCP service を通じて参照する。
client ごとに browser process を起動しないため、同じ profile の同時起動を避けられる。

Nix の反映と旧 Docker runtime の削除は、この directory を削除・初期化しない。
profile を手動で削除すると browser login、session、cache も失われる。
ブラウザが profile の形式を更新することがあるため、古い browser version への
downgrade は別途確認する。

## Hermes profiles

root の `mcp_servers.chrome` は共通 MCP 定義から公式 Home Manager の
`services.hermes-agent.mcpServers` を通じて生成する。named profile は root の
MCP 設定を継承しないため、各 Git source の `config.yaml` に gateway 参照または
次の接続先を置き、公式 `hermes profile install` / `update` で反映する。
既存の同じ HTTP URL はそのまま使える。

```yaml
mcp_servers:
  chrome:
    url: http://127.0.0.1:8765/mcp
```

Hermes の組み込み browser toolset と共通 MCP の server 名 `chrome` は別である。
各 profile で Chrome MCP を使う場合は、profile source で組み込み browser の
有効化設定も確認し、意図した session の tool を選ぶ。

## Service operations and verification

Linux/WSL の状態と log は次で確認する。

```bash
systemctl --user status mcp-chrome.service
journalctl --user -u mcp-chrome.service
```

macOS は `launchctl print "gui/$(id -u)/org.nix-community.home.mcp-chrome"` で
確認する。再起動は Linux/WSL の `systemctl --user restart mcp-chrome.service`、
macOS の `launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.mcp-chrome"`
を使う。
macOS の log は root Hermes home の `mcp-chrome.log` に出力する。

通常の Nix/Home Manager 設定を反映した後、root の接続を確認する。

```bash
hermes mcp test chrome
```

`navigate_page` と `take_snapshot` を含む tool set を discover できることを確認する。
named profile は source 側の MCP 設定を反映した後に確認する。

```bash
hermes -p <name> mcp test chrome
```

Codex は同じ `programs.mcp.servers.chrome` を標準 Home Manager integration から
読み込む。service の更新後は必要に応じて client の MCP 接続を再接続する。

長時間のブラウザ処理は Chrome 操作を逐次化し、各バッチの完了時にページ番号、
候補 ID、URL を checkpoint へ記録する。操作がタイムアウトした場合はそのバッチを
未完了として停止し、限定的な再読込で回復しなければ `mcp-chrome` を再起動して
checkpoint から再開する。
