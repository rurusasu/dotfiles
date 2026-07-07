FROM nousresearch/hermes-agent:latest

USER root

ARG ARTICLE_COLLECTOR_VERSION=v0.6.17

COPY xapi-mcp.sh /usr/local/bin/hermes-xapi-mcp
COPY gh-wrapper.sh /usr/local/bin/gh

RUN python3 - <<'PY'
from pathlib import Path

path = Path("/opt/hermes/gateway/channel_directory.py")
text = path.read_text(encoding="utf-8")
old = 'types="public_channel,private_channel",'
new = 'types="public_channel",'
if old not in text:
    raise SystemExit(f"expected Slack channel directory call not found in {path}")
path.write_text(text.replace(old, new), encoding="utf-8")
PY

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gh \
  && arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
    amd64) article_collector_asset="article-collector-linux-amd64" ;; \
    arm64) article_collector_asset="article-collector-linux-arm64" ;; \
    *) echo "unsupported architecture for article-collector: $arch" >&2; exit 1 ;; \
  esac \
  && curl -fsSL \
    "https://github.com/rurusasu/article-collector/releases/download/${ARTICLE_COLLECTOR_VERSION}/${article_collector_asset}" \
    -o /usr/local/bin/article-collector \
  && chmod +x /usr/local/bin/article-collector \
  && /usr/bin/gh --version \
  && npm --version \
  && npx --version \
  && article-collector --help \
  && chmod +x /usr/local/bin/gh \
  && chmod +x /usr/local/bin/hermes-xapi-mcp \
  && rm -rf /var/lib/apt/lists/*
