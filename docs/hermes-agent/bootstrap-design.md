# Hermes Agent Bootstrap Design

## Status

Approved design for the container-owned Hermes bootstrap used on every host OS.
The implementation is split between this dotfiles repository, the
remote-authoritative root distribution, and the configured named-profile
remotes.

## Goals

- Use one bootstrap implementation inside the Hermes image on every host OS.
- Keep root/default declarative content remote-authoritative.
- Treat existing named-profile declarative allowlists as local-authoritative.
- Publish named profiles through the official Hermes distribution API without
  making a runtime profile home a Git worktree.
- Keep runtime state and secrets outside distribution repositories.
- Keep shared repositories, including lifelog, available to every profile.
- Fail before local transaction and gateway restart when credentials, preflight,
  or profile publication fail.

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
from remote content. The current local layout declares Rick and Hoffman assets,
does not declare RisaRisa assets, and has no Nancy home yet; a future installed
Nancy home controls its own assets through its local allowlist.

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

The required Slack items include `SlackBot-OpenClaw`, `SlackBot-Rick`,
`SlackBot-Hoffman`, `SlackBot-Risarisa`, and `SlackBot-Nancy`; GitHub access is
validated for every configured remote before bootstrap modifies local runtime
data.

## Apply Sequence

1. Build and validate the Compose model, stop the gateway, and read the secret
   payload without logging it.
2. Validate required fields, GitHub credentials, remote identities, and access.
3. Snapshot every existing named profile, complete aggregate preflight, and
   synchronize each exact local snapshot to its configured remote before any
   staging or local transaction.
4. For existing profiles, stage the exact commit reported by publication. For a
   truly missing target only, stage its configured remote first-install ref.
5. Stage the remote-authoritative root distribution and synchronize the shared
   lifelog remote according to its locked read-write policy.
6. Start the local transaction; apply root and named distributions through the
   official Hermes APIs, apply shared working trees, and merge private `.env`
   files with mode `0600`.
7. Validate the installed layout, commit the transaction, report the
   `profile_sync` summary, then recreate and health-check the gateway.

If aggregate profile preflight or publication fails, bootstrap stops before
starting the local transaction. It preserves the profile-sync report. Earlier
remote pushes remain valid because remote commits are outside the local
transaction boundary; they are not rolled back.

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

An operator repairs only the failed profile and redacted category. Fix the
local authoritative profile content, or the owning engine/environment for a
non-content failure, then run the dry-run command and the real command. A
repair is accepted only when the aggregate exits `0` and that profile is
`changed` or `unchanged`.

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
