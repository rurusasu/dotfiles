# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      git libpq-dev build-essential \
    && rm -rf /var/lib/apt/lists/*
ARG COGNEE_COMMIT=d4913de215730bd9825115d978e7842acf0062b9
RUN git clone https://github.com/rurusasu/cognee.git /app/cognee \
    && cd /app/cognee && git checkout ${COGNEE_COMMIT}

WORKDIR /app/cognee
RUN uv venv /app/.venv \
    && uv pip install --python /app/.venv/bin/python \
       -e "."

WORKDIR /app/cognee/cognee-mcp
RUN uv pip install --python /app/.venv/bin/python -e .

COPY skills_tools/ /app/cognee/cognee-mcp/src/skills_tools/

FROM python:3.12-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/cognee /app/cognee
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
    && sed -i 's/\r$//' /app/entrypoint.sh

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

WORKDIR /app/cognee/cognee-mcp
EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.sh"]
