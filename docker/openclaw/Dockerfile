# syntax=docker/dockerfile:1.7

FROM oven/bun:1

WORKDIR /app

# Add node → bun symlink for packages that invoke node directly.
RUN ln -sf /usr/local/bin/bun /usr/local/bin/node

# Install git, SSH client, and GitHub CLI (gh) for GitHub access.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git openssh-client \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# GIT_ASKPASS helper: feeds GITHUB_TOKEN as the HTTPS password at runtime.
# ${GITHUB_TOKEN} is evaluated at shell execution time, not build time.
RUN printf '#!/bin/sh\nif echo "$1" | grep -qi "password"; then echo "${GITHUB_TOKEN}"; else echo "x-access-token"; fi\n' \
    > /usr/local/bin/git-credential-askpass.sh \
    && chmod +x /usr/local/bin/git-credential-askpass.sh

# Install openclaw to /home/bun/.bun (user-home path) so extensions pass
# openclaw's plugin trust validation. Install as root, then chown to bun.
ENV NODE_ENV=production \
    BUN_INSTALL=/home/bun/.bun \
    PATH=/home/bun/.bun/bin:${PATH}

RUN mkdir -p /home/bun/.bun/bin /home/bun/.bun/install/global \
    && bun add -g openclaw \
    # Pre-install acpx into the plugin-bundled path so the ACP runtime backend works
    # at runtime without needing npm (not installed) or a writable filesystem.
    && cd /home/bun/.bun/install/global/node_modules/openclaw/extensions/acpx \
    && bun install --production \
    && cd /app \
    # Install Gemini CLI so sessions_spawn(runtime="acp", agentId="gemini") can work.
    && bun add -g @google/gemini-cli \
    && chown -R bun:bun /home/bun/.bun

# Pre-create data directories with correct ownership.
# ~/.gemini is created here so the named-volume fallback inherits bun ownership.
RUN mkdir -p /app/data/workspace /app/data/.bun \
    && mkdir -p /home/bun/.openclaw /home/bun/.gemini \
    && chown -R bun:bun /app/data /home/bun/.openclaw /home/bun/.gemini

USER bun

# Bake global git config into the image (read-only at runtime is fine).
# safe.directory=* allows git to work in /app/data/workspace regardless of ownership.
RUN git config --global user.name "openclaw" \
    && git config --global user.email "openclaw@container" \
    && git config --global safe.directory "*"

ENTRYPOINT ["openclaw"]
CMD ["gateway"]
