# Action Version Management

## Node.js 24 Compatible Versions (as of 2026-04)

```yaml
actions/checkout@v6
actions/setup-node@v5
actions/setup-python@v6
actions/upload-artifact@v5
actions/download-artifact@v5
github/codeql-action/upload-sarif@v4
docker/setup-buildx-action@v4
docker/login-action@v4
docker/metadata-action@v6
docker/build-push-action@v7
hadolint/hadolint-action@v3.2.0
```

## Check Latest Version

```bash
gh api repos/OWNER/REPO/releases/latest -q .tag_name
```

## Transitive Dependency Problem

Some actions internally use old Node.js 20 actions that you cannot override:

| Action                             | Internal dependency             | Problem                                                           |
| ---------------------------------- | ------------------------------- | ----------------------------------------------------------------- |
| `aquasecurity/trivy-action@0.35.0` | `actions/cache@v4` (Node.js 20) | Used in composite pre-step, `cache: false` doesn't fully suppress |

### Solutions (in order of preference)

1. **Use CLI directly** — install the tool and run commands (see [trivy-cli.md](trivy-cli.md))
2. **Set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`** — suppresses warning but doesn't fix root cause
3. **Disable internal feature** (e.g., `cache: "false"`) — may not work for composite action pre-steps
