# apt-get Patterns

## Cache mount

OK:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    curl \
    git
```

NG:

```dockerfile
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    curl \
    git \
  && rm -rf /var/lib/apt/lists/*
```

Why: cache mount を使えば `rm -rf` は不要。

## --no-install-recommends

OK:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    curl \
    git
```

NG:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y \
    curl \
    git
```

Why: 不要な推奨パッケージが入りイメージが肥大化する。

## Retry/timeout config

OK:

```dockerfile
COPY <<EOF /etc/apt/apt.conf.d/80-retries
Acquire::Retries "5";
Acquire::http::Timeout "45";
Acquire::https::Timeout "45";
EOF

RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    curl \
    git
```

NG:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update -o Acquire::Retries=5 -o Acquire::http::Timeout=45 && \
  apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=45 install -y --no-install-recommends \
    curl \
    git
```

Why: Acquire オプションが重複。`COPY <<EOF` で `apt.conf.d` に切り出すべき。

## Pinned versions

OK:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    curl=7.88.1-10+deb12u8 \
    git=1:2.39.5-0+deb12u2
```

NG:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    curl \
    git
```

Why: バージョン未固定だとビルド再現性がない (hadolint DL3008)。本番用は固定を推奨。

## Third-party repository

OK:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; \
  echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends nodejs
```

NG:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
  apt-get install -y --no-install-recommends nodejs
```

Why: convenience script のパイプ実行はセキュリティリスク。GPG 鍵で署名検証すべき。

## Third-party repository: Google Cloud CLI

OK:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg; \
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    google-cloud-cli
```

NG:

```dockerfile
RUN if [ "${INSTALL_GCLOUD_SDK}" = "true" ]; then \
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
  apt-get update && \
  apt-get install -y \
    google-cloud-cli && \
  rm -rf /var/lib/apt/lists/*; \
  fi
```

Why: cache mount なし、`--no-install-recommends` なし、`rm -rf` 不要、`curl` に `-fsSL` なし（エラー時にサイレント失敗する）。条件分岐による optional install は `docker compose` の `target` でステージを切り替えるべき。

## Key rules

| Rule                      | Description                                       |
| ------------------------- | ------------------------------------------------- |
| `--no-install-recommends` | Always use. Prevents unnecessary packages         |
| `--mount=type=cache`      | Prefer over `rm -rf /var/lib/apt/lists/*`         |
| `sharing=locked`          | Prevents parallel build race conditions           |
| `set -eux`                | Exit on error, undefined vars, debug output       |
| `apt-get update`          | Always run before `apt-get install` in same RUN   |
| Separate config           | Extract Acquire options to `/etc/apt/apt.conf.d/` |
