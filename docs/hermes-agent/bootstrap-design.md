# Hermes Agent Bootstrap Design

## Status

Approved design for an OS-independent Hermes Agent bootstrap. Implementation is
split across the dotfiles repository and the Hermes home/profile distribution
repositories listed below.

## Problem

Hermes setup currently has two independent implementations:

- macOS, Linux, and NixOS source `scripts/sh/hermes-agent.sh`.
- Windows runs `scripts/powershell/handlers/Handler.HermesAgent.ps1`.

The PowerShell handler provisions a GitHub token, while the shell implementation
does not. The container's `gh` wrapper only maps an existing process environment
variable and does not load the active Hermes profile's `.env`. This allows Slack
to start while `gh auth status` reports that no GitHub host is authenticated.

The duplicated setup logic also lets dashboard, Slack, profile, repository, and
runtime configuration drift between operating systems.

## Goals

- Use one bootstrap implementation inside the Hermes image on every host OS.
- Keep `install.sh` and `install.cmd` as the supported top-level entry points.
- Treat GitHub as the source of truth for root and profile declarative content.
- Use Hermes' official profile distribution mechanism for named profiles.
- Keep runtime state and secrets outside Git repositories.
- Make shared repositories such as lifelog available to every profile.
- Fail setup before restarting Hermes when any required credential or source is
  missing or invalid.
- Preserve existing runtime data and roll back partially applied changes.

## Non-Goals

- Replacing Hermes' one-container/many-profiles model.
- Storing secrets in Git, Compose files, command arguments, or image layers.
- Making profile memories or sessions shared through Git.
- Running one gateway container per profile.

## Runtime Layout

Keep the existing bind mount and upstream-compatible root:

```text
host ~/.hermes/                    container /opt/data/ (HERMES_HOME)
├── .env                           root runtime secrets
├── config.yaml                    root declarative config
├── SOUL.md                        root declarative profile
├── profile.yaml
├── profiles/
│   ├── rick/                      official Hermes distribution target
│   ├── hoffman/
│   └── risarisa/
├── shared/
│   └── lifelog/                   writable independent Git repository
├── core/
│   └── lifelog -> ../shared/lifelog
├── memories/                      root runtime state
├── sessions/
└── logs/
```

`/opt/data` is a runtime root, not a Git checkout. This avoids a parent Git
repository containing profile distributions, shared repositories, secrets, and
live state.

`/opt/data/shared/<name>` is the canonical location for repositories shared by
all profiles. `/opt/data/core/lifelog` is accepted only as a migration source
and is absent after a successful apply. New configuration and documentation
use `/opt/data/shared/lifelog`.

## Source Repositories

The bootstrap manifest maps each target to a source and ref:

| Target         | Source                             | Ref    | Update mechanism                |
| -------------- | ---------------------------------- | ------ | ------------------------------- |
| Root/default   | `rurusasu/hermes-home`             | `main` | Root distribution apply         |
| Rick           | `rurusasu/hermes-profile-rick`     | `main` | `hermes profile install/update` |
| Hoffman        | `rurusasu/hermes-profile-hoffman`  | `main` | `hermes profile install/update` |
| Risarisa       | `rurusasu/hermes-profile-risarisa` | `main` | `hermes profile install/update` |
| Shared lifelog | `rurusasu/lifelog`                 | `main` | Locked read-write Git sync      |

Named profile repositories must add `distribution.yaml`. The bootstrap invokes
Hermes' official distribution API so `.env`, `auth.json`, memories, sessions,
logs, workspaces, and other user-owned paths remain untouched. It stages the
declared ref first, then uses forced distribution installation for both initial
and existing profiles. This replaces `config.yaml` with the same ownership
result as `profile update --force-config` without performing a second,
unpinned network fetch.

Hermes explicitly rejects installing a distribution as `default`, so
`hermes-home` uses `root-distribution.yaml`. It lists the root-owned paths that
the bootstrap may replace. The root apply uses the same ownership principles as
Hermes distributions and never modifies user-owned runtime paths.

The dotfiles repository stops generating or patching tracked `SOUL.md`,
`config.yaml`, profile policy, cron, scripts, and MCP blocks. Those files move to
the appropriate root or profile source repository.

## Shared Repository Policy

Shared repositories are declared rather than hard-coded. The initial manifest
entry is equivalent to:

```yaml
shared_repositories:
  - name: lifelog
    source: https://github.com/rurusasu/lifelog.git
    ref: main
    target: /opt/data/shared/lifelog
    mode: read-write
    sync_owner: default
```

Supported policies are:

- `read-only`: bootstrap performs a fast-forward update and profiles do not
  commit or push.
- `read-write`: profiles may edit content, while one declared owner performs
  commit, pull/rebase, and push.

Only the default profile owns the lifelog Git sync cron job. Git operations use
a repository-specific lock under `/opt/data/locks/repositories/` so cron,
installer, and manual sync cannot run concurrently. All profiles use the same
absolute path and follow the shared repository's `AGENTS.md`.

Adding another shared repository requires a manifest entry and declarative
profile guidance, not new OS-specific installer code.

## Bootstrap Components

### `hermes-bootstrap` service

`docker/hermes-agent/compose.yml` defines an explicitly invoked
`hermes-bootstrap` service. It uses the same image and `/opt/data` bind mount as
the gateway, has no published ports, and is not part of normal `compose up`.

The image installs a `/usr/local/bin/hermes-bootstrap` command. It owns:

- manifest validation;
- GitHub credential validation;
- root distribution staging and apply;
- official named-profile distribution install/update;
- shared repository clone and sync;
- root/profile `.env` updates;
- permission enforcement;
- migration, backup, rollback, and result reporting.

The default profile's lifelog cron invokes
`hermes-bootstrap sync-repository lifelog`. This command loads the GitHub token
from the active root `.env` and reuses the same repository identity checks,
lock, forbidden-path checks, commit, rebase, and push implementation as the
installer. Distribution repositories do not carry a second Git sync
implementation.

### Host adapters

The shell and PowerShell adapters only:

1. verify Docker, `op`, and host prerequisites;
2. request the non-secret item plan that `hermes-bootstrap` derives from the
   shared manifest;
3. retrieve each declared 1Password item and stream it immediately as a
   versioned JSON payload to `hermes-bootstrap` over stdin;
4. propagate the bootstrap exit status;
5. start or recreate the Hermes Compose services after success.

Secret values are never passed as command arguments. The adapters do not
implement `.env`, profile, Git, or config merge behavior.

## Installer Integration

The top-level routing remains unchanged:

```text
install.sh
  -> install-macos.sh / install-linux.sh / install-nixos.sh
  -> shared shell adapter
  -> docker compose run --rm --no-deps -T hermes-bootstrap
  -> docker compose up
```

The duplicated Unix `start_hermes_stack` implementations move into the shared
Hermes shell module and accept a Docker runner for normal and docker-group
execution.

```text
install.cmd
  -> scripts/powershell/install.ps1
  -> scripts/powershell/install.admin.ps1
  -> HermesAgentHandler (Phase 2, non-admin, Order 56)
  -> PowerShell adapter
  -> docker compose run --rm --no-deps -T hermes-bootstrap
  -> docker compose up
```

The Windows handler remains non-admin so 1Password desktop integration works.
Its existing Hermes-specific merge and provisioning methods are removed after
the common bootstrap covers their behavior.

## Secret Sources and Targets

The confirmed 1Password sources are:

| Purpose        | Account            | Vault      | Item                     |
| -------------- | ------------------ | ---------- | ------------------------ |
| Dashboard      | `my.1password.com` | `openclaw` | `Hermes Agent Dashboard` |
| GitHub         | `my.1password.com` | `openclaw` | `GitHubUsedOpenClawPAT`  |
| Root Slack     | `my.1password.com` | `openclaw` | `SlackBot-OpenClaw`      |
| Rick Slack     | `my.1password.com` | `openclaw` | `SlackBot-Rick`          |
| Hoffman Slack  | `my.1password.com` | `openclaw` | `SlackBot-Hoffman`       |
| Risarisa Slack | `my.1password.com` | `openclaw` | `SlackBot-Risarisa`      |

The GitHub item uses its `credential` field. The same Hermes-specific PAT is
written to the root and each managed profile as
`GITHUB_PERSONAL_ACCESS_TOKEN`, `GH_TOKEN`, and `GITHUB_TOKEN`.

GitHub authentication is mandatory. The bootstrap verifies the PAT with the
GitHub API and verifies access to every declared private repository before
changing files. Missing, invalid, or unauthorized credentials fail setup.

Slack and dashboard fields are also mandatory. Managed profile Slack tokens are
profile-specific and replace any cloned or stale platform token before a
profile gateway can restart.

Bootstrap generates independent strong random values for `API_SERVER_KEY` and
`HERMES_DASHBOARD_BASIC_AUTH_SECRET`. It persists them only in private
root/profile `.env` files. A repeat apply verifies the supplied dashboard
password against the installed scrypt hash and reuses a valid hash, signing
secret, and API key, avoiding unintended credential rotation. Compose sets
only `API_SERVER_HOST=0.0.0.0` in the container and publishes port `8642` on
host loopback.

## Runtime `gh` Authentication

`docker/hermes-agent/gh-wrapper.sh` resolves credentials in this order:

1. an existing `GH_TOKEN` process variable;
2. `${HERMES_HOME}/.env` for the active root or named profile;
3. `/opt/data/.env` as the shared root fallback.

It maps `GITHUB_PERSONAL_ACCESS_TOKEN` or `GITHUB_TOKEN` to `GH_TOKEN` and then
executes `/usr/bin/gh`. It does not invoke `gh auth login` or create a separate
`hosts.yml` credential store. If no token is available, it exits with an error
that directs the operator to rerun the installer.

Hermes already propagates the active profile's `HERMES_HOME` to subprocesses,
so the same wrapper works for default and named profiles.

## Apply Sequence

1. Build the Hermes image and validate the Compose model.
2. Request and validate the non-secret 1Password item plan.
3. Start `hermes-bootstrap`, retrieving each required item on the host and
   streaming it directly to stdin.
4. Parse the payload without logging it.
5. Validate all required fields, GitHub authentication, manifests, refs, and
   repository access.
6. Stage root and profile distributions before modifying runtime targets.
7. Acquire each shared-repository lock and complete remote synchronization.
8. Snapshot every locally managed target and record a transaction journal.
9. Apply the root distribution.
10. Apply each named profile through the Hermes distribution API.
11. Clone, migrate, or synchronize shared working trees under
    `/opt/data/shared/`.
12. Atomically update root and profile `.env` files with mode `0600` while
    preserving unmanaged keys.
13. Validate the final layout and `gh` authentication in every profile context.
14. Remove the transaction journal and report changed targets without values.
15. Recreate the Hermes gateway and run health checks.

An existing gateway may remain running during validation and staging. Runtime
files are replaced atomically, and the gateway is recreated only after the
transaction succeeds. On failure, the bootstrap rolls back and the installer
returns non-zero without replacing the running gateway.

Remote commit and push operations are outside the local transaction boundary
because they cannot be rolled back safely. They complete before local runtime
files change. If a later local apply fails, the remote synchronization remains
valid and the next installer run resumes idempotently; root, profile, shared
working-tree migration, and `.env` changes under `/opt/data` are rolled back.

## Migration

The migration keeps `/opt/data` as `HERMES_HOME`, so memories, sessions, logs,
browser data, X credentials, and other runtime paths do not move.

- Existing root declarative files are backed up, then replaced only if listed
  by `root-distribution.yaml`.
- Existing named profiles without `distribution.yaml` are converted with
  `hermes profile install --force`; Hermes preserves user-owned paths.
- An existing `/opt/data/core/lifelog` checkout moves atomically to
  `/opt/data/shared/lifelog`; the old path is then absent.
- If both old and new lifelog paths contain data, bootstrap stops and reports a
  migration conflict rather than merging automatically.
- Existing `.env` files retain unmanaged keys. Managed secret keys are replaced
  from 1Password, while a matching dashboard hash and valid independent
  signing/API secrets are preserved for repeat-run idempotency.
- Backups remain until final validation succeeds and are removed only after the
  transaction commits.

## Failure and Security Rules

- Validate all sources and required credentials before writing.
- Reject malformed manifests, unexpected target paths, symlinks in
  distributions, non-fast-forward refs, and repository identity mismatches.
- Constrain every managed path beneath `/opt/data` and reject traversal.
- Use temporary files, `0600` permissions, atomic rename, and rollback backups.
- Redact secret values from normal output, exceptions, Docker logs, and test
  fixtures.
- Do not place the bootstrap payload in a persistent file or process argument.
- Do not persist credentials in Git remote URLs. Git uses `GIT_ASKPASS` with a
  short-lived file removed on exit.
- Refuse shared-repository commits containing likely secret or runtime paths.
- Return distinct non-zero exit codes for input, credential, repository,
  migration, apply, rollback, and validation failures.

## Testing

Distribution source repositories use the local/hosted validation contract in
`distribution-validation-design.md`. GitHub Actions and pre-push invoke the
same full validator. An explicit GitHub billing block may use current-head
local evidence for automatic merge; missing or unknown workflow evidence may
not.

### Bootstrap unit tests

- manifest and payload schema validation;
- path containment and symlink rejection;
- root distribution ownership boundaries;
- profile install/update while preserving user-owned data;
- sanitized profile payloads containing only `distribution.yaml` and declared
  `distribution_owned` paths;
- shared repository clone, fast-forward, read-write sync, and locking;
- `.env` merge, permissions, active-profile resolution, and idempotency;
- missing and invalid GitHub credentials causing no writes;
- rollback after failures at each apply stage;
- log and exception redaction.

### Adapter contract tests

- Bats tests for the shared shell adapter;
- Pester tests for `HermesAgentHandler` and the PowerShell adapter;
- identical versioned payloads and error propagation on every OS;
- no secret values in command arguments or captured logs.

### Container integration tests

Build the real image and use a temporary `HERMES_DATA_DIR` with local bare Git
repositories and fake 1Password responses. Verify initial install, repeat
install, profile update, root update, shared repository migration, rollback,
and gateway configuration without using real credentials.

### Live acceptance

After implementation, run the installer with the confirmed 1Password items and
verify without printing token values:

- `hermes profile list` contains default, rick, hoffman, and risarisa;
- each named profile reports distribution source and version;
- root and every profile pass `gh auth status` or an equivalent API check;
- `/opt/data/shared/lifelog` is one shared checkout visible to all profiles;
- `/opt/data/core/lifelog` does not exist after migration;
- root and profile Slack gateways start with their own app credentials;
- root API, dashboard, browser viewer, cron ticker, and profile gateways are
  healthy;
- a second installer run produces no unintended file changes.

## Implementation Phases

1. Add distribution manifests to the three named-profile repositories and a
   root distribution manifest to `hermes-home`.
2. Move dotfiles-generated declarative config, policies, cron, scripts, and MCP
   settings into their owning distribution repositories.
3. Add the common bootstrap command, Compose service, manifest, transaction,
   shared-repository, and `gh` wrapper behavior in this repository.
4. Reduce the shell and PowerShell implementations to host adapters.
5. Add unit, contract, container integration, migration, and live acceptance
   coverage.
6. Update `profile-home-layout.md`, `browser-mcp.md`, secrets documentation, and
   Taskfile commands after the new runtime is active.
