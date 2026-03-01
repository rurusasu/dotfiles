# syntax=docker/dockerfile:1.7

FROM oven/bun:1

USER root
WORKDIR /app

ENV NODE_ENV=production \
    BUN_INSTALL=/opt/bun \
    PATH=/opt/bun/bin:${PATH}

# Install openclaw globally, then set permissions for non-root runtime user.
RUN mkdir -p /opt/bun \
    && bun add -g openclaw \
    && chmod -R a+rX /opt/bun

# Pre-create data directories with correct ownership.
# Named volume at /app/data is initialized from this layer on first run.
RUN mkdir -p /app/data/workspace /app/data/.bun \
    && chown -R bun:bun /app/data

USER bun

ENTRYPOINT ["openclaw"]
