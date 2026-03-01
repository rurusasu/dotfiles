# syntax=docker/dockerfile:1.7

FROM oven/bun:1

WORKDIR /app

# Add node → bun symlink for packages that invoke node directly.
RUN ln -sf /usr/local/bin/bun /usr/local/bin/node

# Install git + SSH client for GitHub access.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git openssh-client \
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
    && chown -R bun:bun /home/bun/.bun

# Pre-create data directories with correct ownership.
RUN mkdir -p /app/data/workspace /app/data/.bun \
    && mkdir -p /home/bun/.openclaw \
    && chown -R bun:bun /app/data /home/bun/.openclaw

USER bun

# Bake global git config into the image (read-only at runtime is fine).
# safe.directory=* allows git to work in /app/data/workspace regardless of ownership.
RUN git config --global user.name "openclaw" \
    && git config --global user.email "openclaw@container" \
    && git config --global safe.directory "*"

ENTRYPOINT ["openclaw"]
CMD ["gateway"]
