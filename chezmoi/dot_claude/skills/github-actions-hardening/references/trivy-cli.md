# Trivy: Use CLI, Not the Action

## Why

`aquasecurity/trivy-action` internally uses `actions/cache@v4` (Node.js 20) via a composite action pre-step. This cannot be suppressed by `cache: "false"` or `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`.

See: [aquasecurity/trivy-action#528](https://github.com/aquasecurity/trivy-action/issues/528)

## Install Trivy CLI

Pin version in workflow-level `env:` for single source of truth:

```yaml
env:
  TRIVY_VERSION: 0.69.3  # Check: gh api repos/aquasecurity/trivy/releases/latest -q .tag_name
```

Install step (reuse in each job that needs trivy):

```yaml
- name: Install Trivy
  run: |
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin v${{ env.TRIVY_VERSION }}
```

## Scan Types

### Config scan (Dockerfile misconfigurations)

```yaml
- name: Trivy config scan
  run: trivy config --format sarif --output trivy-config.sarif --severity CRITICAL,HIGH .
```

### Filesystem scan (dependency vulnerabilities)

```yaml
- name: Trivy fs scan
  run: trivy fs --format sarif --output trivy-fs.sarif --severity CRITICAL,HIGH .
```

### Image scan (OS/package vulns in built Docker image)

```yaml
- name: Trivy image scan
  run: trivy image --format table --severity CRITICAL,HIGH --exit-code 0 --input /tmp/image.tar.gz
```

## SARIF Upload to GitHub Security

```yaml
- uses: github/codeql-action/upload-sarif@v4
  if: always()
  with:
    sarif_file: trivy-config.sarif
    category: trivy-config
```
