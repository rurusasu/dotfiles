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

Asset ownership follows the same rule for every profile. If a valid local
manifest declares `assets`, regular avatar and portfolio files beneath it are
published; otherwise they are not. Task 5 fixtures exercise declared assets for
Rick, Hoffman, and Nancy and no `assets` declaration for RisaRisa without
turning that fixture layout into a production-state rule.

## Snapshot Boundary

For each existing valid profile, the synchronizer parses and validates the
local manifest, removes runtime `source` and `installed_at` values when it
creates the canonical remote manifest, and builds a private immutable snapshot.
The projection contains exactly:

- canonical `distribution.yaml`;
- generated canonical `.gitignore`; and
- regular files beneath validated `distribution_owned` paths.

It rejects `.env*`, credential filenames such as `auth.json`, Git control
paths, reserved runtime paths such as memories, sessions, logs, plans,
workspaces, caches, and locks, special files, external hard links, symbolic
links, and paths outside the home. Preflight also rejects traversal,
non-portable names, case collisions, unreadable or concurrently replaced
files, and high-confidence secret content. Other regular files beneath a
validated owned file or directory are included; a generic temporary-looking
filename is not excluded merely because of its name.

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
missing-target, or aggregate-preflight failures exit `4`. A standalone
`sync-profiles` command never installs a missing profile. Invalid arguments
exit `2`, manifest validation exits `8`, and unexpected command failures exit
`6`; those failures write a safe message to stderr and do not emit the JSON
report.

The JSON schema is `schema_version: 1`. Its top-level `command` is exactly
`"sync-profiles"`; `dry_run` is a boolean; `status` is exactly `"changed"`,
`"unchanged"`, or `"failed"`; and `profiles` is in manifest order. Every
profile object has exactly the command fields `name`, `status`, `commit`,
`snapshot`, `added`, `modified`, `deleted`, `paths`, `category`, and `message`.
The change fields are arrays of relative paths, and `paths` is their sorted
combined list.

The per-profile values have these exact meanings:

- `unchanged` uses the current remote-head commit, the local snapshot digest,
  empty diff arrays, category `unchanged`, and message
  `profile snapshot already published`.
- A dry-run difference is `changed`, but `commit` is still the current remote
  head because dry-run creates no commit. It reports the real tree diff,
  category `dry_run`, and message `profile snapshot changes detected`.
- A real publication is `changed`, reports the resulting remote commit and
  tree diff, and uses category `published` with message
  `profile snapshot published`.
- A failure after snapshot preparation has `status: "failed"`, `commit: null`,
  the prepared snapshot digest, and empty diff arrays. Credential, missing
  target, malformed-profile, and other pre-snapshot aggregate failures use an
  empty `snapshot` for every profile.

Credential failure marks every profile `failed` with
`credentials_unavailable` / `GitHub credentials are unavailable`. For a
missing or malformed profile, the invalid entry uses its concrete preflight
category, such as `missing_profile`, with message
`local profile snapshot is invalid`; every other entry uses
`aggregate_preflight_blocked` / `profile publication blocked by aggregate
preflight`. A boundary-level repository failure uses
`repository` / `profile synchronization failed` for every entry.

The following reachable real-run example is expanded for readability; actual
stdout is the compact, sorted, single-line encoding described above.

```json
{
  "schema_version": 1,
  "command": "sync-profiles",
  "dry_run": false,
  "status": "changed",
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
      "status": "changed",
      "commit": "2123456789012345678901234567890123456789",
      "snapshot": "c4c2d9e80f1a2b3c4d5e6f789012345678901234567890abcdef1234567890ab",
      "added": [],
      "modified": [],
      "deleted": ["README.md"],
      "paths": ["README.md"],
      "category": "published",
      "message": "profile snapshot published"
    },
    {
      "name": "nancy",
      "status": "changed",
      "commit": "3123456789012345678901234567890123456789",
      "snapshot": "d4c2d9e80f1a2b3c4d5e6f789012345678901234567890abcdef1234567890ab",
      "added": ["assets/nancy-slack-avatar.png"],
      "modified": ["assets/nancy-portfolio.png"],
      "deleted": [],
      "paths": ["assets/nancy-portfolio.png", "assets/nancy-slack-avatar.png"],
      "category": "published",
      "message": "profile snapshot published"
    }
  ]
}
```

The example is a reachable sequential result after successful aggregate
preflight, not a requirement that those profiles always have those outcomes.
For a blocked aggregate preflight, every entry is `failed`: only the invalid
profile has its concrete redacted validation category, while every other entry
uses `aggregate_preflight_blocked`. No remote profile comparison or update
began in that case, every `commit` is `null`, and every `snapshot` and diff
array is empty. A missing target in standalone `sync-profiles` follows this
exit-`4` failure path; only bootstrap `apply` may treat a truly absent target as
a first install.

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
repository validation but before staging or starting the local transaction. It
then stages root, stages profiles in manifest order using either the reported
exact commit or the configured branch for a truly missing target, synchronizes
shared repositories, and only then begins the transaction. The successful
`apply` result includes a `profile_sync` summary whose entries are `changed`,
`unchanged`, or `installed`.

If profile synchronization fails, bootstrap fails before starting the local
transaction; it neither applies runtime distributions nor restarts Hermes.
Pushes completed for earlier profiles remain valid. The Python exception keeps
an internal report, but the public `apply` CLI reduces it to a safe failed-name
message on stderr. Operators obtain per-profile categories from the standalone
`sync-profiles` JSON. Root staging stays remote-authoritative and shared
lifelog continues its ordinary locked read-write Git synchronization.

## Repair Handoff

After an `apply` failure, run standalone `sync-profiles --dry-run` to obtain the
category-bearing JSON; do not expect `apply` stderr to contain that category.
Create a repair task with only the failed profile name and its redacted
`category`. Correct the local authoritative profile data, or correct the owning
engine/environment for a non-content category. Do not repair by checking out,
cloning, or copying remote content into the profile home.

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
