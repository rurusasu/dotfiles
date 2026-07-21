# Hermes Bootstrap Operations

Hermes uses one container-owned bootstrap on every supported host. The host
adapter supplies prerequisites and secrets; it does not write Hermes config,
profiles, repositories, or `.env` files directly.

## Run

Prerequisites are a running Docker daemon, Docker Compose, an authenticated
1Password CLI (`op`), access to the six configured items, and access to the
declared private GitHub repositories. Unix requires native `bash`, `jq`,
`docker`, and `op`. Windows requires `pwsh`, Docker Desktop's native `docker`
and Compose plugin, and an authenticated native `op.exe`; the focused adapter
does not route these commands through WSL.

For a focused rerun on any supported host:

```text
task hermes:bootstrap
```

On Unix, the task sources `scripts/sh/hermes-agent.sh` and invokes its Docker
adapter with the canonical Compose file. On Windows, it runs
`pwsh -NoProfile -File scripts/powershell/hermes-bootstrap.ps1`, a focused
Docker Desktop adapter that does not require WSL, NixOS, or a completed Nix
rebuild. Both adapters run Compose config validation, build `hermes` and
`hermes-bootstrap`, invoke the container bootstrap, and only then recreate the
stack.

`install.cmd` remains the Windows full-machine setup entrypoint and continues
through the PowerShell handler. The exact supported installer chains are:

```text
install.sh -> OS installer -> shell adapter (scripts/sh/hermes-agent.sh) -> hermes-bootstrap container -> compose up
install.cmd -> install.ps1 -> install.admin.ps1 -> HermesAgentHandler -> PowerShell adapter (HermesBootstrap.ps1) -> hermes-bootstrap container -> compose up
```

`task hermes:bootstrap` returns the selected focused adapter status; it neither
runs the full-machine installer nor hides a nonzero result.

## Data Flow

The exact bootstrap chain is:

```text
host adapter
  -> request the non-secret secret plan
  -> fetch six full 1Password item JSON objects
  -> stream header + six item records + end as NDJSON
  -> docker compose run --rm --no-deps -T hermes-bootstrap apply
  -> validate and stage every source
  -> transactional install under /opt/data
  -> docker compose up -d --force-recreate only after success
```

Each of the six NDJSON item records embeds the full object returned by
`op item get <title> --account my.1password.com --vault openclaw --format json`.
The stream is sent directly to container stdin. It is never stored in a file,
logged, or placed in a process argument.

All configured items are mandatory:

| Purpose        | Account            | Vault      | Item title               |
| -------------- | ------------------ | ---------- | ------------------------ |
| Dashboard      | `my.1password.com` | `openclaw` | `Hermes Agent Dashboard` |
| GitHub         | `my.1password.com` | `openclaw` | `GitHubUsedOpenClawPAT`  |
| Root Slack     | `my.1password.com` | `openclaw` | `SlackBot-OpenClaw`      |
| Rick Slack     | `my.1password.com` | `openclaw` | `SlackBot-Rick`          |
| Hoffman Slack  | `my.1password.com` | `openclaw` | `SlackBot-Hoffman`       |
| Risarisa Slack | `my.1password.com` | `openclaw` | `SlackBot-Risarisa`      |

Required field labels, without their values, are:

- `Hermes Agent Dashboard`: `username` accepts `username` or `user name`; `password` accepts `password`.
- `GitHubUsedOpenClawPAT`: `credential` accepts `credential`, `token`, `PAT`, or `password`.
- Each Slack item: `bot_token` accepts `SLACK_BOT_TOKEN`, `bot_token`, or `bot token`; `app_token` accepts `SLACK_APP_TOKEN`, `app_level_token`, `app token`, or `app-level token`; `allowed_users` accepts `SLACK_ALLOWED_USERS`, `allowed_users`, `allowed users`, `allowFrom`, or `allow_from`.

The bootstrap validates GitHub authentication and repository access, then writes
only managed keys to root/profile `.env` files. Secret values never belong in
this repository or these docs.

## Sources And Layout

`/opt/data` is the runtime root, not a Git checkout. Its canonical managed
layout is:

```text
/opt/data/
├── profiles/{rick,hoffman,risarisa}/
├── shared/lifelog/
└── core/lifelog -> ../shared/lifelog
```

The root source is `rurusasu/hermes-home` at `main`; its
`root-distribution.yaml` limits which root paths may be replaced. Rick,
Hoffman, and Risarisa come from their matching
`rurusasu/hermes-profile-<name>` repositories at `main` and are applied with
Hermes' official profile distribution API using `distribution.yaml`.

See [Home/Profile Layout](profile-home-layout.md) for ownership boundaries.

## Transaction And Recovery

Before local writes, bootstrap validates credentials, repository access,
manifests, refs, source ownership, and staged distributions. Shared remote sync
also completes before the local transaction because a remote push cannot be
rolled back safely.

The local transaction uses a single-writer lock and journals snapshots under
`/opt/data/.bootstrap/transactions/`. Root-owned paths, named profiles, shared
working-tree moves, compatibility links, and `.env` files are staged or
snapshotted before replacement. Environment files are atomically renamed with
mode `0600`, preserve unmanaged keys, and replace managed secret keys.

If a local apply or final validation fails, bootstrap restores all recorded
local paths and leaves the existing Compose stack running. A remote lifelog
commit or push completed before the transaction is not reversed; the next run
resumes from that valid remote state. If the process is interrupted, the next
`apply` recovers or cleans the journal before accepting a new transaction.

Repository synchronization uses
`/opt/data/locks/repositories/<name>.lock`. Lock contention fails immediately
instead of waiting indefinitely. After confirming that the other bootstrap or
sync process has exited, rerun the same command.

## Migration And Conflicts

- A legacy real checkout at `/opt/data/core/lifelog` is moved atomically to
  `/opt/data/shared/lifelog`, then replaced by the relative compatibility
  symlink `../shared/lifelog`.
- If both lifelog paths contain real data, bootstrap exits with migration code
  `5`. It does not merge, delete, or choose between them; reconcile or back up
  one path explicitly, then rerun.
- Existing named profiles are installed from their staged official
  distributions with forced distribution ownership. User-owned `.env`,
  `auth.json`, memories, sessions, logs, and workspaces remain outside that
  ownership.
- Existing root files are replaced only when declared by
  `root-distribution.yaml`.
- Repeated successful runs are supported and converge to the same layout.

## Exit Codes

The container command uses stable typed exit codes:

| Code | Meaning                                                       | Operator action                                                |
| ---- | ------------------------------------------------------------- | -------------------------------------------------------------- |
| `0`  | Success                                                       | Compose may start                                              |
| `1`  | Host secret-plan or payload production failed                 | Fix `op`/adapter input and rerun                               |
| `2`  | Invalid command, manifest, payload, or managed env input      | Correct input; no Compose restart                              |
| `3`  | Missing, invalid, or unauthorized credential                  | Repair 1Password/GitHub access                                 |
| `4`  | Repository access, identity, sync, or repository-lock failure | Resolve repository/lock state and rerun                        |
| `5`  | Migration conflict                                            | Reconcile the named old/new paths manually                     |
| `6`  | Apply, staging, cleanup, or active transaction failure        | Inspect redacted diagnostics and rerun/recover                 |
| `7`  | Rollback failure                                              | Preserve the journal and inspect managed paths before retrying |
| `8`  | Final installed-layout validation failed                      | Correct layout/source state and rerun                          |

Compose config, build, bootstrap, and startup failures remain nonzero through
the host adapter. The adapter prints only redacted diagnostics and never runs
`compose up` after an earlier failure.

## Source Validation Gate

The four source repositories use the same `fast` and `full` validator. Local
validator exits are `0` pass, `1` validation failure, `2` prerequisite blocked,
and `3` validator internal error. A result is current only when its `head_sha`
matches local `HEAD` and the pull request head.

The controller exposes these operator states:

| State                 | Meaning                                                                                       |
| --------------------- | --------------------------------------------------------------------------------------------- |
| `PASS_REMOTE`         | Exact-head local full validation and current-head workflow both pass                          |
| `PASS_LOCAL_FALLBACK` | Exact-head local full validation passes and GitHub explicitly reports a billing startup block |
| `FAIL_VALIDATION`     | Local or hosted validation reports failed checks                                              |
| `FIX_FAILED`          | The two-round automated repair limit was reached                                              |
| `ENV_BLOCKED`         | Docker, image, pre-commit, or authentication prerequisite is absent                           |
| `REMOTE_PENDING`      | Current-head workflow is queued or running                                                    |
| `REMOTE_UNKNOWN`      | No usable run and no explicit billing evidence exists                                         |
| `STALE_EVIDENCE`      | Local or remote evidence is for another commit                                                |
| `INTERNAL_ERROR`      | Validator or classifier violated its contract                                                 |

Only `PASS_REMOTE` and `PASS_LOCAL_FALLBACK` authorize merge. Local fallback
requires GitHub-owned current-head evidence that billing, spending, included
usage, storage billing, or an exhausted budget prevented startup. A missing
run, missing API permission, or unknown failure is never billing evidence and
remains `REMOTE_UNKNOWN`. Automated repair is limited to two rounds for the
same repository and failed check set; `ENV_BLOCKED` does not consume a round.

See [Distribution Validation](distribution-validation-design.md) for the full
evidence and remediation contract.
