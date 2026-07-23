# Hermes Agent Bootstrap Design

## Status

Approved design for the container-owned Hermes bootstrap used on every host OS.
The implementation is split between this dotfiles repository, the
remote-authoritative root distribution, and the configured named-profile
remotes.

## Problem

Hermes setup historically had independent shell and PowerShell implementations:

- macOS, Linux, and NixOS source `scripts/sh/hermes-agent.sh`.
- Windows runs `scripts/powershell/handlers/Handler.HermesAgent.ps1`.

The PowerShell handler provisions a GitHub token, while the shell implementation
did not. The container `gh` wrapper originally only mapped an existing process
environment variable rather than the active Hermes profile `.env`. Slack could
therefore start while `gh auth status` had no authenticated GitHub host. The
duplicated setup logic also lets dashboard, Slack, profile, repository, and
runtime configuration drift between operating systems.

## Goals

- Use one bootstrap implementation inside the Hermes image on every host OS.
- Keep root/default declarative content remote-authoritative.
- Treat existing named-profile declarative allowlists as local-authoritative.
- Publish exact named-profile snapshots to their configured remotes, then apply
  the reported commits through the official Hermes distribution API without
  making a runtime profile home a Git worktree.
- Keep runtime state and secrets outside distribution repositories.
- Keep shared repositories, including lifelog, available to every profile.
- Fail before local transaction and gateway restart when credentials, preflight,
  or profile publication fail.

## Non-Goals

- Replacing Hermes' one-container/many-profiles model.
- Storing secrets in Git, Compose files, command arguments, or image layers.
- Making profile memories or sessions shared through Git.
- Running one gateway container per profile.

## Runtime Layout

```text
host ~/.hermes/                    container /opt/data/ (HERMES_HOME)
├── .env                           root runtime secrets
├── config.yaml                    root declarative config
├── SOUL.md                        root declarative profile
├── profile.yaml
├── profiles/
│   ├── rick/                      official Hermes target; local-authoritative when present
│   ├── hoffman/
│   ├── risarisa/
│   └── nancy/
├── shared/
│   └── lifelog/                   writable independent Git repository
├── memories/                      root runtime state
├── sessions/
└── logs/
```

`/opt/data` is a runtime root, not a Git checkout. Its profile homes are also
never Git repositories. The canonical shared path is
`/opt/data/shared/lifelog`; `/opt/data/core/lifelog` is migration-only and is
absent after a successful apply.

## Source And Authority Matrix

The manifest maps each target to a remote and ref. Authority depends on its
content class:

| Target                                                  | Configured source                                | Authority and update mechanism                                                       |
| ------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------ |
| Root/default                                            | `rurusasu/hermes-home`                           | remote-authoritative root distribution apply                                         |
| Named profiles (`rick`, `hoffman`, `risarisa`, `nancy`) | matching `rurusasu/hermes-profile-<name>` remote | existing local allowlist snapshot to exact remote commit, then official Hermes apply |
| Shared lifelog                                          | `rurusasu/lifelog`                               | locked read-write Git synchronization                                                |

The manifest, rather than a hard-coded list, determines named profiles. An
existing valid profile reads its own local `distribution.yaml`. The bootstrap
generates a canonical remote manifest and `.gitignore`, snapshots only regular
files permitted by `distribution_owned`, and publishes an exact remote tree.
That tree contains only the canonical `.gitignore`, canonical
`distribution.yaml`, and owned paths. It deletes stale remote workflows,
README files, validators, tests, scripts, and every other allowlist-external
path.

The snapshot lives in bootstrap-owned private storage. No normal or dry-run
operation checks out or clones into `/opt/data/profiles/<name>`, and no normal
or dry-run operation changes local profile bytes or modes. Empty directories
are not represented by Git.

Only a target directory that is truly absent uses its configured remote as a
first-install seed. Existing malformed profiles are failed, never overwritten
from remote content. Assets are manifest-generic: any profile, including Nancy,
publishes avatar or portfolio files only when its valid local
`distribution.yaml` declares the corresponding `assets` path. Task 5 fixtures
cover declared assets for Rick, Hoffman, and Nancy and no `assets` declaration
for RisaRisa.

## Bootstrap Components

`docker/hermes-agent/compose.yml` defines an explicitly invoked
`hermes-bootstrap` service. It uses the gateway image and `/opt/data` bind
mount, has no published ports, and is not part of normal `compose up`. Its
command owns manifest and credential validation, profile snapshotting and
publication, root and profile staging/apply, lifelog synchronization, `.env`
updates, transaction management, and redacted reporting.

Host adapters only check prerequisites, obtain the non-secret secret plan,
stream 1Password JSON to the container, propagate its status, and recreate the
gateway after successful bootstrap. They do not implement profile Git or merge
behavior. Secret values are never command arguments or persistent payload
files.

On Windows, `HermesAgentHandler` remains Phase `2`, order `56`, with
`RequiresAdmin = false`. Running in the user context is required so native
`op.exe` can use 1Password desktop integration; elevating this handler would
break that credential path.

The required Slack items include `SlackBot-OpenClaw`, `SlackBot-Rick`,
`SlackBot-Hoffman`, `SlackBot-Risarisa`, and `SlackBot-Nancy`; GitHub access is
validated for every configured remote before bootstrap begins new staging or
transaction writes. Crash-journal recovery is the exception: it runs first and
may restore or remove previously journaled managed paths before secret or
credential validation.

## Shared Lifelog Operation

Lifelog is not an exact named-profile mirror. The manifest declares it as a
normal read-write shared repository with `sync_owner: default`. Its owner runs
`hermes-bootstrap sync-repository lifelog`, which uses the runtime token
precedence, validates the canonical checkout, acquires
`/opt/data/locks/repositories/lifelog.lock`, and performs the ordinary
commit/rebase/push workflow. All profiles continue to use
`/opt/data/shared/lifelog`.

## Apply Sequence

1. Build and validate the Compose model and stop the gateway.
2. Load the manifest and recover or clean any crash journal. This recovery may
   restore or remove previously journaled managed paths before credentials are
   validated.
3. Read the secret payload without logging it, then validate required fields,
   GitHub credentials, remote identities, and access.
4. Snapshot every existing named profile, complete aggregate preflight, and
   synchronize each exact local snapshot to its configured remote before any
   staging or local transaction.
5. Stage the remote-authoritative root distribution.
6. In manifest order, stage each named profile: use the exact commit reported by
   publication for an existing profile, or the configured branch only for a
   truly missing first install.
7. Synchronize each shared repository remote, including lifelog under its
   locked read-write policy.
8. Call `Transaction.begin`, apply the root distribution, apply the staged
   profiles in manifest order through the official Hermes API, publish shared
   working trees, and merge private `.env` files with mode `0600`.
9. Validate the installed layout, commit the transaction, report the
   `profile_sync` summary, then recreate and health-check the gateway.

If aggregate profile preflight or publication fails, bootstrap stops before
root/profile staging, shared synchronization, or the local transaction.
Snapshot-preflight rejection happens before `profile_report` exists; public
`apply` stderr is `profile snapshot rejected (<category>)`, with no profile
name or report. Standalone `sync-profiles --dry-run` repeats aggregate
preflight and identifies the invalid profile and category in its JSON. A
nonzero post-preflight publication report instead produces
`named profile repository sync failed: <failed names>`; the Python exception
retains that report internally, but the CLI does not serialize its categories.
In both cases `apply` stdout is empty.

Dry-run is limited to preflight and diff inspection. It never pushes, so a
changed entry has category `dry_run` and cannot reproduce push-only categories
such as `push_rejected` or `push_race_exhausted`. To obtain a push-only category,
run standalone real `sync-profiles` and inspect its JSON. That aggregate command
also processes every other manifest profile and may publish their changes;
successful pushes, including those completed before another profile fails,
remain valid and are not rolled back.

## Profile Sync Result Contract

Operators use these exact commands:

```text
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap sync-profiles --dry-run
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap sync-profiles
```

`sync-profiles` aggregates all manifest profiles. It writes one compact sorted
JSON result line to stdout for handled success and failure, with empty stderr.
Its `command` is `sync-profiles`; aggregate `status` is `changed`, `unchanged`,
or `failed`; profile entries contain `name`, `status`, `commit`, `snapshot`,
`added`, `modified`, `deleted`, `paths`, `category`, and `message`.

Credential failure exits `3`. Repository, lock, remote, or aggregate-preflight
failure exits `4`. Unexpected CLI failures use the standard redacted stderr
boundary. A JSON result paired with nonzero exit remains a failed aggregate.

Aggregate preflight completes before any push. Subsequent profile Git work runs
sequentially; a failure does not prevent later attempts. One race retry fetches
and rebuilds the snapshot; a same-tree remote descendant is accepted, and a
second race is `push_race_exhausted`.

## Failure And Recovery

After a snapshot-preflight `apply` failure, use standalone dry-run JSON to
identify the failed profile and category. Fix that local authoritative profile
or its owning engine/environment, and rerun dry-run until aggregate preflight is
green. Then run real `sync-profiles`. If real publication fails, assign its
failed profile and push-only category from that real JSON report, repair the
owning engine/environment, and repeat dry-run before another real attempt. A
repair is accepted only when the real aggregate exits `0` and the repaired
profile is `changed` or `unchanged`.

The root remains remote-authoritative throughout recovery. Lifelog remains a
normal locked read-write Git checkout and is not part of named-profile exact
mirroring.

## Future `hermes-home` Work

The two-hour aggregate cron handoff and dedicated private Slack channel ID are
explicitly future Task 7 work in `hermes-home`; they are not deployed by this
design's current dotfiles implementation. A future root-owned wrapper must call
the aggregate command and must not import remote content into an existing local
named profile.

## Verification

`task hermes:bootstrap:test` covers manifest-generic four-profile sequencing,
including Nancy; existing-local snapshots; missing-only first install; invalid
existing profiles; exact remote deletion; local immutability; aggregate
preflight; sequential continuation; retry and same-tree descendant acceptance;
compact JSON; exit codes; and redaction.

Exact named-profile mirrors intentionally delete repository-local workflows,
pre-commit configuration, validators, and tests. Their replacement gate is the
runtime aggregate snapshot preflight plus the dotfiles engine's pre-commit,
GitHub Actions, and container integration suite. Repository-local `fast`/`full`
validation remains scoped only to remote-authoritative or other source
repositories that actually retain that tooling.
