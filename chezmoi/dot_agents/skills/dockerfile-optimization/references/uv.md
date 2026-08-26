# uv Patterns

## Install: COPY --from

OK:

```dockerfile
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
```

NG:

```dockerfile
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
```

Why: `COPY --from` は単一レイヤー、キャッシュ効率が高い。curl install はネットワーク依存でビルド再現性が低い。

## Python install

OK:

```dockerfile
ARG PYTHON_VERSION=3.12
RUN uv python install ${PYTHON_VERSION}
```

NG:

```dockerfile
RUN apt-get update && apt-get install -y python3
```

Why: uv なら任意バージョンを簡単にインストール可能。apt は OS リポジトリのバージョンに依存。

## Dependency install: bind mount

OK:

```dockerfile
ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --group dev --no-install-project
```

NG:

```dockerfile
ENV VIRTUAL_ENV="${WORKDIR}/.venv" \
    PATH="${WORKDIR}/.venv/bin:${PATH}"

COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --group dev --no-install-project

COPY . .
```

Why: `COPY . .` はソース全体がイメージレイヤーに残る。bind mount ならレイヤーに残らず `.dockerignore` 管理も不要。

## VIRTUAL_ENV placement

OK:

```dockerfile
ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

RUN --mount=type=bind,target=. \
    python -c "import mypackage"
```

NG:

```dockerfile
ENV VIRTUAL_ENV="${WORKDIR}/.venv" \
    PATH="${WORKDIR}/.venv/bin:${PATH}"

RUN --mount=type=bind,target=. \
    python -c "import mypackage"  # ImportError!
```

Why: `--mount=type=bind,target=.` は WORKDIR 全体をマウントするため、WORKDIR 内の `.venv` が隠される。`/opt/venv` なら影響を受けない。

## --frozen vs --locked

OK (CI/本番):

```dockerfile
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project
```

OK (開発):

```dockerfile
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project
```

NG:

```dockerfile
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-install-project
```

Why: `--frozen` は uv.lock 更新を完全に防止（再現性）。`--locked` は pyproject.toml との整合性を検証。オプションなしだと uv.lock が更新される可能性がある。

## --no-install-project

OK:

```dockerfile
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project

# Source is provided via bind mount or volume mount
# from src.xxx import ... works via PYTHONPATH
```

NG:

```dockerfile
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen

# Project itself is editable-installed but source not in image
# ImportError at runtime!
```

Why: `--no-install-project` なしだとプロジェクト自体を editable install しようとするが、bind mount ではソースがレイヤーに残らないため runtime でエラー。依存パッケージだけインストールし、ソースは volume mount で提供するのが正しい。

## PYTHONPATH setting

OK:

```dockerfile
ARG WORKDIR=/backend
WORKDIR ${WORKDIR}

ENV PYTHONPATH=${WORKDIR}

# Source provided via volume mount at runtime
# python -m src.worker.celery_beat works
# from src.core.config import settings works
```

NG:

```dockerfile
ARG WORKDIR=/backend
WORKDIR ${WORKDIR}

# No PYTHONPATH set

# python -m src.worker.celery_beat
# ModuleNotFoundError: No module named 'src'
```

Why: `--no-install-project` を使う場合、プロジェクトは editable install されないため、Python はソースパッケージの場所を知らない。`PYTHONPATH` を WORKDIR に設定すれば、`/backend/src/` が `src` パッケージとして認識される。`python -m src.xxx` や `from src.xxx import ...` が動作する。

## Cache mount

OK:

```dockerfile
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project
```

NG:

```dockerfile
ENV UV_CACHE_DIR=/var/cache/uv
RUN mkdir -p ${UV_CACHE_DIR} && chmod -R 777 ${UV_CACHE_DIR}
RUN uv sync --frozen --no-install-project
```

Why: `--mount=type=cache` はレイヤー外にキャッシュを持つ。`ENV` + `mkdir` はイメージサイズを増やす。

## Builder stage: output path

OK:

```dockerfile
FROM development AS builder
RUN --mount=type=bind,target=. \
    --mount=type=cache,target=/tmp/pyinstaller_cache \
    pyinstaller --noconfirm --workpath /tmp/build --distpath /tmp/dist specs/app.spec
```

NG:

```dockerfile
FROM development AS builder
RUN --mount=type=bind,target=. \
    --mount=type=cache,target=/tmp/pyinstaller_cache \
    pyinstaller --noconfirm --workpath /tmp/build --distpath dist specs/app.spec
```

Why: bind mount 内（`dist`）に出力するとレイヤーに残らない。`/tmp/dist`（bind mount 外）に出力すればレイヤーに残る。

## Production: distroless

OK:

```dockerfile
FROM gcr.io/distroless/base-debian13:nonroot AS production
ARG WORKDIR=/app
WORKDIR ${WORKDIR}

# Shared libs from builder
COPY --from=development /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/
COPY --from=development /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/

# PyInstaller output
COPY --from=builder --chown=nonroot:nonroot /tmp/dist/app/ ${WORKDIR}/

CMD ["./app"]
```

NG:

```dockerfile
FROM python:3.12-slim AS production
COPY --from=builder /app/dist/app/ /app/
CMD ["./app"]
```

Why: distroless は最小限のランタイムで攻撃面が小さい。python-slim は不要なツール（shell, package manager）を含む。

## Double uv sync

OK:

```dockerfile
# Dependencies via bind mount (cached until pyproject.toml/uv.lock change)
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --group dev --no-install-project

# Source provided via volume mount at runtime
```

NG:

```dockerfile
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --group dev --no-install-project

COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --group dev
```

Why: 2 回目の `uv sync` は不要。`--no-install-project` で依存だけインストールすれば、ソースは `from src.xxx import ...` で動作する（editable install 不要）。

## Key rules

| Rule                    | Description                                                |
| ----------------------- | ---------------------------------------------------------- |
| `COPY --from`           | Prefer over curl install for uv binary                     |
| `--frozen`              | Always use for CI/production builds (lock file unchanged)  |
| `--no-install-project`  | Use when source is provided via bind/volume mount          |
| `PYTHONPATH=${WORKDIR}` | Required with `--no-install-project` for module imports    |
| `VIRTUAL_ENV=/opt/venv` | Place outside WORKDIR to avoid bind mount shadowing        |
| `--mount=type=cache`    | Use for `/root/.cache/uv`                                  |
| `--distpath /tmp/dist`  | Output outside bind mount so artifacts persist in layer    |
| Single `uv sync`        | Don't run twice; dependencies + volume mount is sufficient |
