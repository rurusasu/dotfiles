# syntax=docker/dockerfile:1.7

FROM oven/bun:1

WORKDIR /app

# Add node → bun symlink for packages that invoke node directly.
RUN ln -sf /usr/local/bin/bun /usr/local/bin/node

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

ENTRYPOINT ["openclaw"]
CMD ["gateway"]
