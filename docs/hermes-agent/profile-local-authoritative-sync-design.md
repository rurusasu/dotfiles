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
stderr is empty, even for an aggregate failure. After that line is written and
flushed normally, the process status is authoritative: credential
unavailability exits `3`; repository, lock, remote, missing-target, or
aggregate-preflight failures exit `4`. A standalone `sync-profiles` command
never installs a missing profile. Invalid arguments exit `2`, manifest
validation exits `8`, and unexpected command failures exit `6`; those failures
write a safe message to stderr and do not emit the JSON report.

The existing CLI BrokenPipe behavior is the exception to exit-status authority.
If stdout closes while the result is written, the command returns `0`, even
when the report would have exited nonzero. Automation must consume stdout to
completion and must not accept an early-closing pipe's `0` as sync success.

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
- An ordinary per-profile Git or publication failure after snapshot preparation
  does not replace other completed profile results; their available snapshots,
  commits, and diffs remain in the aggregate. The failed entry has status
  `failed` and retains its prepared snapshot digest; an unavailable commit is
  `null` and unavailable diff arrays are empty.
- Credential, missing-target, malformed-profile, and other pre-snapshot
  aggregate failures use an empty `snapshot` for every profile.
- A final top-level snapshot scratch cleanup failure replaces all completed
  results with aggregate `cleanup_failed` entries. Every replacement has an
  empty snapshot, `commit: null`, and empty diff arrays.

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

After any crash-journal recovery, bootstrap validates credentials and
repositories, then runs the same snapshot-and-publication phase before staging
or starting a new local transaction. It then stages root, stages profiles in
manifest order using either the reported exact commit or the configured branch
for a truly missing target, runs `validate_chrome_mcp_sources` over the staged
root and profiles, synchronizes shared repositories, and only then begins the
transaction. Existing named-profile publication has already completed before
this staged Chrome gate. Its reported remote commits remain valid and are not
rolled back if Chrome validation fails; apply stops before shared-repository
synchronization or `Transaction.begin`. The successful `apply` result includes
a `profile_sync` summary whose entries are `changed`, `unchanged`, or
`installed`.

If profile synchronization fails, bootstrap fails before starting the local
transaction; it neither applies runtime distributions nor restarts Hermes.
Pushes completed for earlier profiles remain valid. Snapshot preflight throws
before `profile_report` is assigned, so public `apply` stderr is only
`profile snapshot rejected (<category>)`; it has no profile name or report.
Standalone dry-run repeats aggregate preflight and identifies that profile and
category in its JSON.
Only a nonzero post-preflight publication report produces
`named profile repository sync failed: <failed names>` and attaches the report
to the Python exception. Later staging, transaction, validation, cleanup, or
rollback failures can retain the already-created report as well. The CLI never
serializes it. By default `apply` emits one safe stderr message and no failed
JSON result; with `HERMES_BOOTSTRAP_DEBUG=1`, it may append a sanitized
public-boundary traceback that retains neither tokens nor the raw internal
exception graph. The publication message has failed names but no categories.
Root staging stays remote-authoritative and shared lifelog continues its
ordinary locked read-write Git synchronization.

Every post-preflight apply publication message is therefore a cleanup inventory
trigger before retry or closure: its hidden category could be
`cleanup_failed`. Inventory profile scratch and outer apply scratch directly
under `/opt/data`, plus private shared-repository stages matching
`/opt/data/shared/.hermes-repository-*`. If all guarded inventories are reliably
empty, continue ordinary push-failure recovery. A candidate or indeterminate
check activates the full quiescent, mount-aware, atomic-quarantine procedure.
Later successful dry-run/real results do not waive the earlier inventories.

Snapshot-preflight rejection remains separate because its category is public
and publication has not started. If final outer apply scratch cleanup fails,
`could not clean bootstrap staging resources` replaces the snapshot rejection;
that outer error can also replace a post-preflight publication or later primary
failure and can retain an internal profile report that the CLI does not expose.
It is therefore an indeterminate trigger requiring both the direct-child
profile inventory for `.hermes-profile-snapshots-*`,
`.hermes-profile-sync-*`, and `askpass-*` and the outer inventory for
`.hermes-bootstrap-*` under `/opt/data`, plus the direct-child private
shared-repository stage inventory for `.hermes-repository-*` under
`/opt/data/shared`. A candidate or indeterminate determination activates the
same full recovery procedure. An exact
`profile snapshot rejected (cleanup_failed)` message means final outer scratch
cleanup did not replace it and does not alone trigger these inventories.

## Repair Handoff

After a snapshot-preflight `apply` failure, run standalone
`sync-profiles --dry-run` to obtain the failed profile and category. Use
dry-run only to make aggregate preflight green and inspect the diff. A changed
dry-run entry has category `dry_run`; because no push occurs, dry-run cannot
reproduce `push_rejected`, `push_race_exhausted`, or another push-only
category.

To obtain a push-only category, run standalone real `sync-profiles` and use its
JSON report. The real aggregate processes every manifest profile in sequence
and may push changes for profiles other than the original failure. Any
successful push remains valid and is not rolled back. If real publication
fails, create the repair task from the failed profile name and redacted
category in that real report. Correct the local authoritative profile data or
the owning engine/environment; do not repair by checking out, cloning, or
copying remote content into the profile home.

1. Run the dry-run command above until aggregate preflight is green.
2. Run the real command above.
3. If real publication fails, use its JSON profile/category for the next repair
   and repeat dry-run before another real attempt.
4. Accept the repair only when the real aggregate exit is `0`, the repaired
   profile's status is `changed` or `unchanged`, and any `cleanup_failed`
   conditions below are also satisfied.

A different failed profile is a separate repair task. A nonzero aggregate exit
means the original repair is not complete. If any report used category
`cleanup_failed`, a later successful run is also insufficient by itself:
follow the guarded recovery procedure in [Hermes Bootstrap
Operations](bootstrap.md). Keep every automated, installer, Compose, and manual
sync launch path, including the gateway and scheduler, disabled under one
maintenance owner; reject candidate subtrees containing mounts; atomically
isolate verified artifacts in the same-filesystem private quarantine; and
require final profile-scratch, outer-bootstrap, private shared-repository stage,
quarantine, and mount inventories to be clean before re-enabling launch paths.

The same unified pre-retry inventories are mandatory when failed `apply`
exposes only `named profile repository sync failed: <failed names>` or
`could not clean bootstrap staging resources`. Do not infer an ordinary push
category from either message. Reliably empty inventories return the named
publication error to normal push repair; the outer cleanup error retains its
cleanup diagnosis until its cleanup fault is repaired. A candidate or
indeterminate result activates the full cleanup procedure.

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

Because a real exact sync deletes allowlist-external workflows, pre-commit
configuration, validators, and tests, named-profile mirror repositories do not
retain a repository-local validation contract. This named-mirror contract
supersedes that scope of the older validation design. Runtime aggregate
preflight and the dotfiles engine's pre-commit, GitHub Actions, and pinned
integration gate replace it; see the current scoped
[Distribution Validation Design](distribution-validation-design.md).

Production acceptance is a dry run followed by a real aggregate run, with
inspection that each remote tree contains only the two canonical control files
and its local owned paths. Verify the profile homes are unchanged, then confirm
a repeat real run is `unchanged` without creating commits. The direct
`/opt/data` inventory for `.hermes-profile-snapshots-*`,
`.hermes-profile-sync-*`, `askpass-*`, `.hermes-bootstrap-*`, and
`.hermes-profile-cleanup-quarantine-*`, together with the direct
`/opt/data/shared` inventory for `.hermes-repository-*`, must also be empty,
with no candidate or descendant mount issue. Aggregate success does not waive
the quiescent cleanup and quarantine evidence.
