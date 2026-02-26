# Binary Install Patterns

## COPY --from (official Docker image)

公式 Docker イメージからバイナリを直接コピーする。最も安全で高速。

### 条件

- ツールが公式 Docker イメージを公開している（Docker Hub, ghcr.io, gcr.io 等）
- イメージ内にスタンドアロンのバイナリがある（静的リンクまたは依存が少ない）

### 確認方法

- README / ドキュメントに `docker pull <tool>` の記載がある
- GitHub の Dockerfile で `FROM scratch` や `FROM alpine` を使っている（= 静的バイナリの可能性が高い）

OK:

```dockerfile
COPY --from=arigaio/atlas:latest /atlas /usr/local/bin/atlas
COPY --from=bufbuild/buf:latest /usr/local/bin/buf /usr/local/bin/buf
COPY --from=hadolint/hadolint:latest /bin/hadolint /usr/local/bin/hadolint
COPY --from=sqlc/sqlc:latest /workspace/sqlc /usr/local/bin/sqlc
COPY --from=golangci/golangci-lint:latest /usr/bin/golangci-lint /usr/local/bin/golangci-lint
```

NG:

```dockerfile
RUN curl -sSf https://atlasgo.sh | sh
```

Why: `curl | sh` はリモートスクリプトを無検証で実行するためセキュリティリスク。

## GitHub Releases から直接ダウンロード

公式 Docker イメージがない場合の代替手段。

OK:

```dockerfile
ARG SQLC_VERSION=1.27.0
RUN set -eux; \
  curl -fsSL "https://github.com/sqlc-dev/sqlc/releases/download/v${SQLC_VERSION}/sqlc_${SQLC_VERSION}_linux_amd64.tar.gz" \
    -o /tmp/sqlc.tar.gz; \
  tar -xzf /tmp/sqlc.tar.gz -C /usr/local/bin sqlc; \
  rm /tmp/sqlc.tar.gz
```

NG:

```dockerfile
RUN curl -LO https://github.com/sqlc-dev/sqlc/releases/download/v1.27.0/sqlc_1.27.0_linux_amd64.tar.gz && \
  tar -xf sqlc_1.27.0_linux_amd64.tar.gz && \
  mv sqlc /usr/local/bin/sqlc && \
  rm sqlc_1.27.0_linux_amd64.tar.gz && \
  chmod +x /usr/local/bin/sqlc
```

Why: バージョンがハードコードで重複、`-fsSL` なし、作業ファイルがカレントに散乱、`tar -C` で直接配置すれば `mv` と `chmod` は不要。

## 優先順位

| 優先度 | 方法                             | 条件                                          |
| ------ | -------------------------------- | --------------------------------------------- |
| 1      | `COPY --from=<image>`            | 公式 Docker イメージ + スタンドアロンバイナリ |
| 2      | GitHub Releases 直接ダウンロード | リリースページにバイナリ公開                  |
| 3      | apt リポジトリ追加 + install     | ベンダーが apt リポジトリを提供（例: gcloud） |
| 4      | `curl \| sh`                     | 上記すべて不可の場合のみ（非推奨）            |
