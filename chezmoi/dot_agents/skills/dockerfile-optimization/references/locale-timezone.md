# Locale & Timezone Configuration

Debian slim イメージはロケールデータが削除されているため、明示的な設定が必要。

## C.UTF-8 vs en_US.UTF-8

| 項目           | `C.UTF-8`                  | `en_US.UTF-8`              |
| -------------- | -------------------------- | -------------------------- |
| 追加パッケージ | 不要（glibc 内蔵）         | `locales` 必要（+15-30MB） |
| ソート順       | バイト順（高速）           | 言語ルール準拠（低速）     |
| UTF-8 対応     | 完全（日本語・絵文字含む） | 完全                       |
| 再現性         | 高い                       | ディストロ間で差異あり     |

**推奨: `C.UTF-8`**。追加パッケージ不要でイメージサイズに影響なし。

## Locale 設定

### C.UTF-8（推奨）

OK:

```dockerfile
ENV LANG=C.UTF-8 \
  LC_ALL=C.UTF-8
```

Why: Debian 11+ では `C.UTF-8` が glibc に内蔵されており、`locales` パッケージ不要。全 Unicode に対応。

### en_US.UTF-8（必要な場合のみ）

OK:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends locales && \
  localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

ENV LANG=en_US.UTF-8 \
  LC_ALL=en_US.UTF-8
```

NG:

```dockerfile
RUN apt-get update && apt-get install -y locales && \
  sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
  locale-gen && \
  rm -rf /var/lib/apt/lists/*
```

Why: `sed` で `/etc/locale.gen` を書き換えるより `localedef` の方が直接的。cache mount を使えば `rm -rf` も不要。

## Timezone 設定

OK:

```dockerfile
ENV TZ=Asia/Tokyo

RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && \
  apt-get install -y --no-install-recommends tzdata && \
  ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
  echo ${TZ} > /etc/timezone
```

NG:

```dockerfile
RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata && \
  rm -rf /var/lib/apt/lists/*
```

Why: `DEBIAN_FRONTEND` はコマンドごとに設定するより `ENV` で宣言する方が一貫性がある。symlink + `/etc/timezone` の両方を設定しないとツール間で不整合が起きる。cache mount を使えば `rm -rf` は不要。

## DEBIAN_FRONTEND

OK:

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
```

NG:

```dockerfile
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y ...
```

Why: 全 RUN で一貫して適用されるべき。`ENV` で宣言すれば各 RUN に個別指定不要。

注意: マルチステージビルドのプロダクションステージでは不要（apt を使わないため）。

## 統合パターン

```dockerfile
FROM debian:bookworm-slim AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LANG=C.UTF-8 \
  LC_ALL=C.UTF-8 \
  TZ=Asia/Tokyo \
  DEBIAN_FRONTEND=noninteractive
```

`C.UTF-8` + `TZ` の ENV のみで十分な場合、`tzdata` パッケージも不要（ベースイメージに `/usr/share/zoneinfo` が含まれている場合）。ただし Debian slim では `tzdata` が必要。

## ENV 変数の意味

| 変数              | 役割                                            |
| ----------------- | ----------------------------------------------- |
| `LANG`            | `LC_*` カテゴリのデフォルト値                   |
| `LC_ALL`          | 全 `LC_*` カテゴリを強制上書き（最優先）        |
| `TZ`              | タイムゾーン（`/etc/localtime` symlink と併用） |
| `DEBIAN_FRONTEND` | apt の対話モード抑制                            |
