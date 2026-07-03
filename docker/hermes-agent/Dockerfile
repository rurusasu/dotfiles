FROM nousresearch/hermes-agent:latest

USER root

COPY xapi-mcp.sh /usr/local/bin/hermes-xapi-mcp
COPY gh-wrapper.sh /usr/local/bin/gh

RUN apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && /usr/bin/gh --version \
  && npm --version \
  && npx --version \
  && chmod +x /usr/local/bin/gh \
  && chmod +x /usr/local/bin/hermes-xapi-mcp \
  && rm -rf /var/lib/apt/lists/*
