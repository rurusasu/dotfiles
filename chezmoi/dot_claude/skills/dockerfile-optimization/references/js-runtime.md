# JS Runtime Install Patterns

## ランタイム選択

| ランタイム | 方法                   | メリット                       |
| ---------- | ---------------------- | ------------------------------ |
| bun        | `COPY --from=oven/bun` | 単一バイナリ、高速、npm 互換   |
| Node.js    | nodesource apt repo    | エコシステム成熟、全ツール対応 |

bun は `bunx` で `npx` を代替でき、MCP サーバーの実行にも対応。
Node.js 固有の機能が不要なら bun を推奨。

## bun

単一バイナリで `COPY --from` が可能。`bunx` で `npx` を代替。

OK:

```dockerfile
COPY --from=oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx
```

NG:

```dockerfile
RUN curl -fsSL https://bun.sh/install | bash
```

Why: `COPY --from` の方が高速かつキャッシュ効率が良い。`curl | sh` は不要。

## Node.js (nodesource)

Node.js が必須の場合のみ使用。

OK:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  set -eux; \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; \
  echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends nodejs
```

NG:

```dockerfile
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
  apt-get install -y nodejs
```

Why: `setup_*.x` スクリプトは deprecated。GPG キー検証 + `signed-by` が推奨。
