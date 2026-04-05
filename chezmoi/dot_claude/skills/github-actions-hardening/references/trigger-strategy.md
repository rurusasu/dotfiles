# Workflow Trigger Strategy

## Principle: Don't run what's already validated

| Event | CI (lint/test) | Security scan | Docker build | Docker push |
|---|---|---|---|---|
| PR to main | ✅ | — | — | — |
| push to main (merge) | — | ✅ | ✅ (smoke test) | — |
| `v*` tag | — | ✅ | ✅ | ✅ |
| weekly schedule | — | ✅ | — | — |

- **PR**: lint → test only. Merge is the gate.
- **push to main**: Security + build. CI already passed in PR.
- **tag**: Full pipeline. Security gates build; build gates push.
- **weekly**: Security scan only — catch new CVEs in dependencies.

## Security Must Gate Builds

Source-level scans run **before** docker build. No point building if vulnerabilities exist.

```yaml
build:
  needs: [trivy-config, trivy-fs, npm-audit]
  if: github.event_name == 'push'

image-scan:
  needs: build
  if: startsWith(github.ref, 'refs/tags/')

push:
  needs: [build, image-scan]
  if: startsWith(github.ref, 'refs/tags/')
```

## Conditional Patterns

```yaml
# Only on tags — login, save artifact, scan, push
if: startsWith(github.ref, 'refs/tags/')

# Only on push events (not schedule)
if: github.event_name == 'push'

# Tag or schedule (e.g., security scans)
if: startsWith(github.ref, 'refs/tags/') || github.event_name == 'schedule'
```

## Workflow Consolidation

### Merge related workflows into one file

Lint and test → single `ci.yml` with job dependencies:

```yaml
jobs:
  hadolint: ...     # parallel lint
  eslint: ...       # parallel lint
  prettier: ...     # parallel lint
  ruff: ...         # parallel lint

  vitest:
    needs: [eslint, prettier]   # test after its lint
  pytest:
    needs: [ruff]
  build-check:
    needs: [eslint, prettier]
```

Security + docker build + push → single `docker-publish.yml` with conditional jobs.

### Rule

If workflow B should only run after workflow A passes, they belong in the **same file** with `needs:`.
