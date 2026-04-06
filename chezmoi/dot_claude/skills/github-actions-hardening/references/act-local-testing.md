# Local Testing with act

[nektos/act](https://github.com/nektos/act) runs GitHub Actions locally via Docker.

## Install

```bash
# Windows
winget install nektos.act

# macOS
brew install act

# Linux
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

## Configure (first run)

```bash
# Medium image (recommended, ~500MB)
echo '-P ubuntu-latest=catthehacker/ubuntu:act-latest' > ~/.actrc
```

## Usage

```bash
# Run specific job
act push -W .github/workflows/docker-publish.yml -j trivy-config --container-architecture linux/amd64

# Run all jobs for an event
act push -W .github/workflows/ci.yml

# Dry run (list jobs)
act push -W .github/workflows/ci.yml -l
```

## What to Verify

- Action/CLI installation succeeds
- CLI tools run correctly (trivy, hadolint, etc.)
- No Node.js deprecation warnings appear
- Workflow YAML syntax is valid

## Known Limitations

| Step                         | Local behavior                     |
| ---------------------------- | ---------------------------------- |
| `codeql-action/upload-sarif` | ❌ Fails (needs GitHub API)        |
| `docker/login-action`        | ❌ Fails (needs secrets)           |
| `actions/upload-artifact`    | ⚠️ Limited (no GitHub storage)     |
| Docker-in-Docker             | ⚠️ Needs extra config              |
| `GITHUB_TOKEN`               | ⚠️ Scopes differ from real runners |

These failures are expected and do not indicate real problems — the steps that matter (install, scan, build) can be validated locally.
