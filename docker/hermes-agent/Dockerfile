FROM nousresearch/hermes-agent:latest

USER root

COPY xapi-mcp.sh /usr/local/bin/hermes-xapi-mcp

RUN apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && gh --version \
  && npm --version \
  && npx --version \
  && chmod +x /usr/local/bin/hermes-xapi-mcp \
  && rm -rf /var/lib/apt/lists/*
