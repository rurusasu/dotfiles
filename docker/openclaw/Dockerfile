# syntax=docker/dockerfile:1.7

FROM node:22-bookworm-slim

ARG OPENCLAW_VERSION=2026.3.2
ARG GEMINI_CLI_VERSION=0.31.0

WORKDIR /app

COPY entrypoint.sh /usr/local/bin/openclaw-entrypoint.sh
COPY config/gemini.settings.json /app/gemini.settings.json
COPY config/acpx.config.json /app/acpx.config.json
COPY tests/ /app/tests/

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git openssh-client unzip \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI for built-in sandbox (spawns sibling containers via mounted socket).
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker

# Install bun for runtime skills while keeping Node/npm as primary runtime.
ENV BUN_INSTALL=/home/bun/.bun
RUN mkdir -p /home/bun \
    && curl -fsSL https://bun.sh/install | bash

ENV NODE_ENV=production \
    HOME=/home/bun \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_LOGLEVEL=warn \
    PATH=/home/bun/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN npm install -g openclaw@${OPENCLAW_VERSION} \
    && npm --prefix /usr/local/lib/node_modules/openclaw/extensions/acpx install --omit=dev \
    && ln -sf /usr/local/lib/node_modules/openclaw/extensions/acpx/node_modules/.bin/acpx /usr/local/bin/acpx \
    && npm install -g @google/gemini-cli@${GEMINI_CLI_VERSION} \
    && npm install -g @anthropic-ai/claude-code \
    && npm install -g @zed-industries/claude-agent-acp \
    && npm cache clean --force

# GIT_ASKPASS helper: feeds GITHUB_TOKEN env var to git credential prompts.
RUN printf '#!/bin/sh\nif echo "$1" | grep -qi "password"; then echo "${GITHUB_TOKEN}"; else echo "x-access-token"; fi\n' \
    > /usr/local/bin/git-credential-askpass.sh \
    && chmod +x /usr/local/bin/git-credential-askpass.sh

RUN mkdir -p /app/data/workspace /app/data/.bun \
    && mkdir -p /home/bun/.openclaw /home/bun/.gemini /home/bun/.bun /home/bun/.acpx /home/bun/.claude \
    && chmod +x /usr/local/bin/openclaw-entrypoint.sh \
    && chown -R 1000:1000 /app/data /home/bun

USER 1000:1000

RUN git config --global user.name "openclaw" \
    && git config --global user.email "openclaw@container" \
    && git config --global safe.directory "*"

ENTRYPOINT ["/usr/local/bin/openclaw-entrypoint.sh"]
CMD ["gateway"]
