# syntax=docker/dockerfile:1

# ============================================================
# Stage 1: 依存関係インストール（キャッシュ効率重視）
# ============================================================
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      git libpq-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

# cognee ソースを取得（コミットが変わらない限りキャッシュされる）
ARG COGNEE_COMMIT=3b7551b
RUN git clone https://github.com/rurusasu/cognee.git /app/cognee \
    && cd /app/cognee && git checkout ${COGNEE_COMMIT} \
    && rm -rf .git

# venv 作成 + 依存インストール（cognee ソースが変わらない限りキャッシュ）
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /app/.venv \
    && uv pip install --python /app/.venv/bin/python /app/cognee \
    && uv pip install --python /app/.venv/bin/python /app/cognee/cognee-mcp

# skills_tools は頻繁に変更されるため最後にコピー（キャッシュ無効化を最小限に）
COPY skills_tools/ /app/cognee/cognee-mcp/src/skills_tools/

# ============================================================
# Stage 2: ランタイム（最小イメージ）
# ============================================================
FROM python:3.13-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /usr/sbin/nologin app

COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --from=builder --chown=app:app /app/cognee/cognee-mcp/src /app/src
COPY --chown=app:app entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
    && sed -i 's/\r$//' /app/entrypoint.sh \
    && mkdir -p /app/data && chown app:app /app/data

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    SYSTEM_ROOT_DIRECTORY=/app/data/.cognee_system \
    DATA_ROOT_DIRECTORY=/app/data/.data_storage

USER app
WORKDIR /app
EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.sh"]
