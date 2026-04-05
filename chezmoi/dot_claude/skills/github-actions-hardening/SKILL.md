---
name: github-actions-hardening
description: |
  Harden GitHub Actions workflows for zero-warning, efficient CI/CD.
  Use when:
  - Creating or reviewing GitHub Actions workflows
  - Fixing Node.js deprecation warnings in workflows
  - Designing CI/CD pipeline trigger strategies
  - Integrating security scanning (Trivy, npm audit) into pipelines
  - Upgrading action versions
  - Setting up local workflow testing with act
  Triggers: "github actions", "CI/CD", "workflow", "trivy", "node.js deprecation", "act local test"
---

# GitHub Actions Hardening

## Workflow

1. Check all action versions → See [references/action-versions.md](references/action-versions.md)
2. Design trigger strategy → See [references/trigger-strategy.md](references/trigger-strategy.md)
3. Consolidate workflows → Sequential jobs belong in one file with `needs:`
4. Replace problematic actions with CLI → See [references/trivy-cli.md](references/trivy-cli.md)
5. Verify locally with act → See [references/act-local-testing.md](references/act-local-testing.md)
6. Run checklist before merge

## Key Principles

- **Security gates build** — source-level scans (`needs:`) before docker build
- **Don't re-run what's validated** — PR runs CI; merge runs build; tag runs push
- **Avoid transitive dependency traps** — if an action wraps a CLI, use the CLI directly
- **Pin versions in `env:`** — single source of truth, not hardcoded in multiple steps

## Checklist: New Workflow Review

1. All actions on latest major version — `gh api repos/OWNER/REPO/releases/latest -q .tag_name`
2. No transitive Node.js 20 dependencies — check action's `action.yml` for composite steps
3. Triggers match intent — PR for validation, push for build, tag for release
4. Security gates build — `needs: [security-jobs]`
5. No redundant runs — CI doesn't re-run after merge if PR already validated
6. Conditional steps — `if: startsWith(github.ref, 'refs/tags/')` for tag-only work
7. Version pinned in `env:` — not hardcoded in multiple places
8. Local verification — `act` run passes without warnings
