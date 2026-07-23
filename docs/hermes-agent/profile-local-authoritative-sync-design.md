# Hermes Profile Local-Authoritative Sync Design

## Status

Implemented in the `dotfiles` Hermes bootstrap service. This document replaces
the named-profile source-of-truth statements in
`bootstrap-design.md`; the root Hermes distribution and shared repositories
retain their separate ownership rules.

## Authority Model

The three managed content classes deliberately use different authority models:

| Content        | Authoritative location                                     | Synchronization model                                                           |
| -------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Named profile  | Existing `/opt/data/profiles/<name>` declarative allowlist | immutable local snapshot to configured remote, then exact commit through Hermes |
| Root/default   | `rurusasu/hermes-home`                                     | remote distribution to local runtime                                            |
| Shared lifelog | `/opt/data/shared/lifelog`                                 | normal locked read-write Git repository                                         |

`docker/hermes-agent/bootstrap-manifest.yaml` currently declares four named
profiles: `rick`, `hoffman`, `risarisa`, and `nancy`. The manifest is the
configuration source for their name, remote, branch, and target; operations and
tests must not assume a fixed three-profile set.

For an existing valid named profile, the local `distribution.yaml` and its
`distribution_owned` allowlist are authoritative. Remote changes never flow
back into that existing home. The home remains a Hermes distribution target,
not a Git worktree: the synchronizer never clones or checks out into it and
does not alter its bytes or modes. Empty directories are intentionally absent
from the remote projection because Git cannot represent them.

Only a truly missing profile target is a first install. Bootstrap may stage the
configured remote for that target and install it through the official Hermes
distribution API. An existing malformed or incomplete target is not missing:
it fails closed and is never replaced from remote content.

At the Task 6 inspection point, Rick and Hoffman locally declare `assets` and
therefore publish their Slack avatar and portfolio image files. RisaRisa has no
locally declared `assets` path. Nancy is declared by the manifest but its local
profile home is missing, so it has no local snapshot or assets to publish until
the first install has created a valid local manifest. Thereafter Nancy assets
are included only if its own local `distribution_owned` declares them.

## Snapshot Boundary

For each existing valid profile, the synchronizer parses and validates the
local manifest, removes runtime `source` and `installed_at` values when it
creates the canonical remote manifest, and builds a private immutable snapshot.
The projection contains exactly:

- canonical `distribution.yaml`;
- generated canonical `.gitignore`; and
- regular files beneath validated `distribution_owned` paths.

It excludes `.env`, `auth.json`, credentials, `.git`, runtime memories,
sessions, logs, plans, workspaces, caches, locks, temporary files, special
files, hard-link violations, symbolic links, and paths outside the home. The
preflight also rejects traversal, reserved paths, case collisions, unreadable
files, and secret candidates.

The remote tree is an exact projection, not a repository workspace. It contains
only `.gitignore`, `distribution.yaml`, and declared owned paths. Each real
publication stages additions, modifications, and deletions, so stale remote
README files, workflows, validators, tests, and other allowlist-external paths
are deleted. A local deletion of an owned file deletes it remotely. No force
push is used.

## Operator Command

Run the aggregate command from the repository root. These are the supported
dry-run and real forms:

```text
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap sync-profiles --dry-run
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap sync-profiles
```

The command processes every manifest profile in manifest order. `--dry-run`
does the same aggregate local preflight and remote comparison, reports changed
relative paths, and does not commit or push. Neither form logs file contents,
credentials, authenticated URLs, environment values, or token-bearing command
arguments.

On a handled sync result, stdout is exactly one compact, sorted JSON line and
stderr is empty, even for an aggregate failure. The process status is still
authoritative: credential unavailability exits `3`; repository, lock, remote,
or aggregate-preflight failures exit `4`. Argument and unexpected command
errors follow the normal bootstrap CLI error path and write a redacted message
to stderr instead of a result document.

The JSON schema is `schema_version: 1`. Its top-level `command` is exactly
`"sync-profiles"`; `dry_run` is a boolean; `status` is exactly `"changed"`,
`"unchanged"`, or `"failed"`; and `profiles` is in manifest order. Every
profile object has exactly the command fields `name`, `status`, `commit`,
`snapshot`, `added`, `modified`, `deleted`, `paths`, `category`, and `message`.
The change fields are arrays of relative paths, and `paths` is their sorted
combined list.

```json
{
  "schema_version": 1,
  "command": "sync-profiles",
  "dry_run": false,
  "status": "failed",
  "profiles": [
    {
      "name": "rick",
      "status": "changed",
      "commit": "0123456789012345678901234567890123456789",
      "snapshot": "a4c2d9e80f1a2b3c4d5e6f789012345678901234567890abcdef1234567890ab",
      "added": ["assets/rick-slack-avatar.png"],
      "modified": ["config.yaml"],
      "deleted": [],
      "paths": ["assets/rick-slack-avatar.png", "config.yaml"],
      "category": "published",
      "message": "profile snapshot published"
    },
    {
      "name": "hoffman",
      "status": "unchanged",
      "commit": "1123456789012345678901234567890123456789",
      "snapshot": "b4c2d9e80f1a2b3c4d5e6f789012345678901234567890abcdef1234567890ab",
      "added": [],
      "modified": [],
      "deleted": [],
      "paths": [],
      "category": "unchanged",
      "message": "profile snapshot already published"
    },
    {
      "name": "risarisa",
      "status": "failed",
      "commit": null,
      "snapshot": "c4c2d9e80f1a2b3c4d5e6f789012345678901234567890abcdef1234567890ab",
      "added": [],
      "modified": [],
      "deleted": [],
      "paths": [],
      "category": "push_race_exhausted",
      "message": "profile publication changed repeatedly"
    },
    {
      "name": "nancy",
      "status": "failed",
      "commit": null,
      "snapshot": "",
      "added": [],
      "modified": [],
      "deleted": [],
      "paths": [],
      "category": "aggregate_preflight_blocked",
      "message": "profile publication blocked by aggregate preflight"
    }
  ]
}
```

The example illustrates a result shape, not a requirement that those profiles
have those outcomes. For a blocked aggregate preflight, the invalid profile has
its redacted validation category and all other entries are `failed` with
`aggregate_preflight_blocked`; no remote profile comparison or update began.

## Publication And Failure Semantics

Aggregate preflight completes for every existing profile before any push. The
synchronizer copies approved files to bootstrap-owned private storage, then
uses that snapshot for Git work. This prevents a concurrent Hermes edit from
mixing versions in a commit and keeps local profile bytes and modes immutable.

After preflight, profiles run sequentially under per-profile repository locks.
A post-preflight Git failure for one profile is recorded but does not stop
later profiles from being attempted. Earlier successful pushes remain valid
and are not rolled back. A normal push race gets one retry: the synchronizer
fetches the new remote head, rebuilds the same expected tree, and retries. It
accepts a remote descendant when that descendant has the same expected tree;
a second race failure is reported as `push_race_exhausted`.

Bootstrap runs the same snapshot-and-publication phase after credential and
repository validation but before it starts the local transaction. It stages
the resulting exact commits and applies them through the official Hermes
distribution API. Its successful `apply` result includes a `profile_sync`
summary whose four entries are `changed`, `unchanged`, or `installed`.

If profile synchronization fails, bootstrap fails before starting the local
transaction; it neither applies runtime distributions nor restarts Hermes.
Pushes completed for earlier profiles remain valid. Root staging stays
remote-authoritative and shared lifelog continues its ordinary locked
read-write Git synchronization.

## Repair Handoff

Create a repair task with only the failed profile name and its redacted
`category`. Correct the local authoritative profile data, or correct the
owning engine/environment for a non-content category. Do not repair by
checking out, cloning, or copying remote content into the profile home.

1. Run the dry-run command above.
2. Run the real command above.
3. Accept the repair only when the aggregate exit is `0` and the repaired
   profile's status is `changed` or `unchanged`.

A different failed profile is a separate repair task. A nonzero aggregate exit
means the original repair is not complete.

## Future Cron Handoff (Task 7, `hermes-home`)

Two-hour scheduling and Slack delivery are not deployed by this Task 6 change.
Task 7 in `hermes-home` may add a root-owned wrapper that invokes the aggregate
command and may configure its dedicated private Slack channel ID there. This
document makes no claim that a cron job, a channel ID, or Slack delivery is
currently installed. That future handoff remains local-to-remote only and must
not apply remote content into an existing named profile.

## Verification Coverage

The Task 5 tests cover four manifest profiles, including Nancy in bootstrap
sequencing and the profile-sync summary. They cover deterministic allowlist
generation, canonical manifests, exact-tree deletion, immutable local
snapshots, dry-run behavior, aggregate preflight, sequential continuation,
one retry and race exhaustion, same-tree descendant acceptance, credential
exit `3`, repository/preflight exit `4`, compact JSON stdout, and redacted
stderr behavior.

Production acceptance is a dry run followed by a real aggregate run, with
inspection that each remote tree contains only the two canonical control files
and its local owned paths. Verify the profile homes are unchanged, then confirm
a repeat real run is `unchanged` without creating commits.
