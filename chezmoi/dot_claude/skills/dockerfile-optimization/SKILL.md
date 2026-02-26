---
name: dockerfile-optimization
description: |
  Optimize Dockerfiles for smaller images, faster builds, and better security.
  Use when:
  - Creating new Dockerfiles from scratch
  - Reviewing or refactoring existing Dockerfiles
  - Debugging slow Docker builds or large image sizes
  - Installing specific tools (apt-get, uv, npm, CLI tools, AI agents)
  - Setting up multi-stage builds or distroless production images
  - Fixing hadolint warnings (DL3008, DL3015, DL4006, etc.)
  - Configuring locale, timezone, or environment variables
  Triggers: "optimize Dockerfile", "reduce image size", "speed up Docker build", "install X in Docker", "hadolint", "distroless", "multi-stage build"
---

# Dockerfile Optimization

## Core Patterns

Always use these patterns when writing Dockerfiles.

### Cache Mounts

```dockerfile
# apt (always include both, with sharing=locked)
--mount=type=cache,target=/var/lib/apt,sharing=locked
--mount=type=cache,target=/var/cache/apt,sharing=locked

# pip / uv
--mount=type=cache,target=/root/.cache/uv

# npm
--mount=type=cache,target=/root/.npm
```

### Bind Mount

```dockerfile
# Prefer bind mount over COPY for build-only files
RUN --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen

# Full source bind (output outside mount so artifacts persist)
RUN --mount=type=bind,target=. \
    python -m build --outdir /tmp/dist
```

### Shell

```dockerfile
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
```

### Security

```dockerfile
# Non-root user
RUN groupadd -g 1000 app && useradd -u 1000 -g app app
USER app

# Build-time secrets (never in ENV or COPY)
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci
```

### Linting

```bash
hadolint Dockerfile
```

| Rule   | Fix                                               |
| ------ | ------------------------------------------------- |
| DL3008 | Pin versions: `curl=7.88.1-10+deb12u8`            |
| DL3015 | Add `--no-install-recommends`                     |
| DL4006 | Add `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` |

## References

Read the appropriate reference when working with specific tools or patterns.

| When                                                           | Read                                                |
| -------------------------------------------------------------- | --------------------------------------------------- |
| Installing packages with apt-get                               | [apt-get.md](references/apt-get.md)                 |
| Installing binaries (GitHub Releases, COPY --from)             | [binary-install.md](references/binary-install.md)   |
| Installing bun or Node.js                                      | [js-runtime.md](references/js-runtime.md)           |
| Installing CLI tools (starship, fzf, fd, rg, gh, task, etc.)   | [cli-tools.md](references/cli-tools.md)             |
| Setting up pre-commit in Docker                                | [pre-commit.md](references/pre-commit.md)           |
| Installing AI agent CLIs (Claude Code, Codex, Gemini, Copilot) | [ai-agents.md](references/ai-agents.md)             |
| Using uv for Python dependency management                      | [uv.md](references/uv.md)                           |
| Configuring locale or timezone                                 | [locale-timezone.md](references/locale-timezone.md) |
