# Hermes Profile Sync Operation Lock Design

## Status

Approved design amendment for the local-authoritative named-profile
synchronization described in
`profile-local-authoritative-sync-design.md`. This amendment resolves the final
review findings for concurrent bootstrap operations, post-snapshot local drift,
and scratch cleanup guarantees.

## Decision

Hermes bootstrap uses one cooperative engine lock per data root and treats the
bootstrap execution context as trusted. The lock serializes every mutating
bootstrap command from before recovery or scratch creation until all transaction
and scratch cleanup is complete.

The implementation runs inside the pinned Linux container. Host operating
systems use the same Compose command, manifest paths, and lock protocol; no host
UID mapping, privileged helper, or host-specific cleanup command is introduced.

## Threat Model

The supported model includes:

- untrusted or malformed remote repositories;
- malformed, unsafe, or concurrently edited local profile content;
- crashes and partial failures;
- concurrent bootstrap commands that participate in the engine lock;
- symbolic links, special files, unexpected mounts, and accidental pathname
  replacement; and
- a trusted kernel, filesystem, container runtime, and bootstrap execution
  context.

The supported model does not include an actively malicious process that has the
same effective privileges and write access while deliberately bypassing the
engine lock. Pathname-based `unlink` and `rmdir` cannot provide an atomic
identity-check-and-delete guarantee against that actor. Root, kernel, and
filesystem compromise are also outside the model.

Documentation and tests must not claim that cleanup can never delete a
replacement created by an uncooperative same-privilege attacker. Such an
attacker requires a separately privileged cleanup service and protected parent
directory, which is intentionally outside this cross-platform bootstrap design.

## Engine Lock

The canonical lock is `/opt/data/locks/bootstrap-engine.lock`. It is a
nonblocking exclusive advisory lock with the same no-follow, regular-file,
single-link, owner, mode, parent-identity, and redacted-error rules used by the
existing repository and transaction locks.

The lock covers:

- `apply`, beginning before `Transaction.recover_if_needed`;
- `sync-profiles`, including snapshot creation, every remote comparison and
  push, askpass cleanup, Git scratch cleanup, and aggregate snapshot cleanup;
- `sync-repository`, including migration, remote synchronization, publication,
  and cleanup; and
- all nested profile and shared-repository locks.

It is released only after commit or rollback and every tracked private artifact
has either been removed successfully or reported as a cleanup failure. Read-only
`secret-plan` and `validate` do not acquire it.

Repository locks remain in place to preserve repository-specific invariants,
but they are subordinate to the engine lock. Code that performs a mutating
operation receives or asserts the held engine-lock capability and must not
create an independent top-level lock domain.

Lock contention fails immediately through the existing redacted repository
failure boundary. A lock file may persist after release; lock ownership, not
file existence, determines contention.

## Local Drift Revalidation

The initial aggregate profile snapshot remains the only source used for remote
publication. After profile publication, root/profile staging, staged Chrome MCP
validation, and shared remote synchronization, `apply` performs a second full
profile snapshot before `Transaction.begin`.

The second snapshot must match the first in all of these properties:

- the exact set of existing and missing profile targets;
- canonical `distribution.yaml` bytes;
- generated `.gitignore` bytes;
- relative path inventory;
- regular-file modes and sizes;
- per-file SHA-256 values; and
- aggregate snapshot digest.

Metadata-only comparison is insufficient. A same-size edit with restored
timestamps, mode change, addition, deletion, rename, directory replacement, or
newly created previously missing target must be detected.

Any mismatch fails with the redacted category `local_profile_changed` before
`Transaction.begin`, local distribution mutation, environment merge, final
validation, or restart. Remote pushes completed from the first immutable
snapshot remain valid; the next successful run republishes the newer local
state.

There is also a final no-overwrite guard inside named-profile apply:

- a missing target may be installed from the configured exact remote commit;
- an existing target that already equals the staged local projection is a
  no-op; and
- an existing target that differs from the staged projection fails closed and
  is never passed to Hermes with `force=True`.

This guard preserves local authority even if a non-bootstrap writer changes an
existing profile after the second snapshot. Bootstrap never repairs an existing
local profile from remote bytes.

## Cleanup Contract

Private scratch creation remains exclusive, mode `0700`, no-follow, and
descriptor-anchored. Normal cleanup runs while the engine lock is held and
retains:

- root and parent identity checks;
- type-aware, no-follow traversal;
- mount and device-boundary rejection;
- bounded directory and output handling;
- redacted failure reporting; and
- operator inventory and quiescent recovery for retained artifacts.

The cleanup implementation does not use repeated quarantine renames,
`renameat2`, or terminal pathname rechecks to claim protection from an
uncooperative same-privilege attacker. If identity, mount, inventory, or I/O
validation fails, cleanup leaves the uncertain root intact when possible,
returns failure, and does not scan or delete artifacts owned by another
invocation.

Cleanup ownership has explicit terminal states:

- `active`: cleanup or release may be attempted;
- `cleaned`: repeated cleanup returns success;
- `released`: ownership was transferred by a verified publication move; and
- `failed`: repeated cleanup continues to return failure and never masks the
  unresolved artifact.

## Cross-Repository Publication Gate

The committed dotfiles fixture for `scripts/profile_sync.sh` must match the
committed `hermes-home` source by bytes, Git blob ID, SHA-256, and Git tree mode
`100755`.

The host-side verifier is part of `task hermes:bootstrap:test`, so the local
pre-commit hook runs it against the real sibling `hermes-home` Git worktree.
The hook is triggered by changes to `docker/hermes-agent/`, `Taskfile.yml`,
`.pre-commit-config.yaml`, or the Hermes bootstrap workflow. GitHub Actions
checks out `rurusasu/hermes-home` at the validated provenance commit and runs
the same verifier before the pinned container suite. The private checkout uses
the `HERMES_HOME_READ_TOKEN` repository secret, provisioned with read-only
Contents access; the pinned source commit must already exist on that remote.

The publication procedure still reruns this gate twice:

1. before the dotfiles pull request is published; and
2. again immediately before the `hermes-home` pull request is published, after
   the dotfiles pull request has merged.

A mismatch blocks publication and requires an intentional fixture and
provenance update.

## Verification

Tests must prove:

- a second mutating command cannot create scratch, push, or begin a transaction
  while the engine lock is held;
- lock acquisition precedes recovery and scratch creation;
- release follows success, rollback, cleanup failure, and unexpected failure;
- the next process can recover after an interrupted apply;
- every listed local-drift class fails before `Transaction.begin` and preserves
  local bytes and modes;
- a previously missing profile created during apply is not overwritten;
- an existing profile changed after the second snapshot is not force-installed;
- ordinary cleanup succeeds and anomaly cleanup remains redacted and
  fail-closed;
- failed cleanup cannot become a later successful result on the same cleanup
  object;
- publication succeeds only after private cleanup ownership reaches the
  `released` state;
- declared empty owned roots remain invalid, while nested empty directories are
  omitted from the Git projection because Git cannot represent them; and
- the host-side provenance gate rejects dirty, untracked, mismatched, or
  non-`100755` source and fixture state.

The complete bootstrap suite and repository pre-commit hooks must pass before
publication. After the ordered merges, production acceptance still requires a
successful manual cron run, a Slack result in `hermes-cron-results`, and one
subsequent scheduled run.
