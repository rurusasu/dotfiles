# Hermes Bootstrap Operations

Hermes uses one container-owned bootstrap on every supported host. The host
adapter supplies prerequisites and secrets; it does not directly write Hermes
config, profiles, repositories, or `.env` files.

## Run Bootstrap

For a focused full bootstrap on any supported host, run:

```text
task hermes:bootstrap
```

The task validates Compose, builds the Hermes and bootstrap services, streams
the required 1Password data to the container, runs bootstrap, and recreates the
stack only after success. The bootstrap manifest currently declares Slack items
for the root/default profile and four named profiles: Rick, Hoffman, RisaRisa,
and Nancy.

The successful bootstrap JSON contains `status: "applied"`, the four profile
names, `repositories: ["lifelog"]`, and `profile_sync`. `profile_sync` maps
each named profile to `changed`, `unchanged`, or `installed`; `installed` is
only the truly missing first-install case.

## Sync Existing Named Profiles

Use the aggregate profile command before and after a local declarative repair:

```text
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap sync-profiles --dry-run
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap sync-profiles
```

It processes every profile declared in
`docker/hermes-agent/bootstrap-manifest.yaml` in manifest order. Do not replace
these commands with a clone or checkout inside a profile home.

For every existing valid named profile, the local `distribution.yaml` and
`distribution_owned` allowlist are authoritative. The service creates a private
immutable snapshot, projects it into a temporary Git repository, and pushes a
normal fast-forward update. It then stages the same reported commit and uses
the official Hermes distribution API during bootstrap. The profile home itself
stays non-Git and both dry runs and real sync preserve local bytes and modes.

The remote tree is exact: canonical `.gitignore`, canonical
`distribution.yaml`, and declared owned paths only. Stale remote README files,
workflows, validators, tests, or other allowlist-external files are deleted.
Empty directories are not represented in Git.

The configured manifest currently includes `rick`, `hoffman`, `risarisa`, and
`nancy`. Do not use an obsolete three-profile list in a procedure or test.
Rick and Hoffman currently declare `assets`, so their local Slack avatar and
portfolio images are owned. RisaRisa does not declare assets. Nancy's local
home is currently absent; it has no snapshot or assets until its permitted
first install creates a valid local manifest, after which its own local
allowlist controls assets.

## First Install And Bootstrap Ordering

Bootstrap validates credentials and repository access before profile publication.
It snapshots all existing profiles, completes their exact local-to-remote
publication before staging, and stages the exact returned commits. Only then
does it begin the normal transaction that applies root, named profiles, shared
repositories, and environment files.

A target directory that is truly absent is seeded from its configured remote
for the first official Hermes install. An existing malformed or incomplete
profile is not absent: bootstrap fails before its transaction and never falls
back to a remote overwrite.

If synchronization fails, bootstrap does not begin its local transaction or
restart Hermes. It preserves the profile-sync report for diagnostics. Earlier
remote pushes remain valid because remote commits cannot be rolled back; a
subsequent run reports them as `unchanged` when the remote tree matches the
same local snapshot.

Root `hermes-home` remains remote-authoritative. `shared/lifelog` remains the
normal locked read-write Git repository owned for synchronization by the default
profile. The local-first named-profile policy does not change either model.

## Reading Results And Exit Codes

`sync-profiles` writes one compact, sorted JSON result line to stdout for both
success and handled sync failure; stderr is empty in those cases. The object
has `schema_version: 1`, `command: "sync-profiles"`, a boolean `dry_run`, an
aggregate `status`, and ordered `profiles` entries. Aggregate status is
`changed`, `unchanged`, or `failed`, not `success`.

Each profile entry includes `name`, `status`, `commit`, `snapshot`, `added`,
`modified`, `deleted`, `paths`, `category`, and `message`. The three diff
fields and `paths` are arrays of relative paths; `paths` is the sorted combined
list. Treat `category` and `message` as redacted diagnostics.

| Exit | Meaning                                            | Operator action                                                      |
| ---- | -------------------------------------------------- | -------------------------------------------------------------------- |
| `0`  | Every profile is `changed` or `unchanged`          | Continue or accept the repair                                        |
| `3`  | Credentials unavailable                            | Repair the runtime GitHub credential source, then rerun              |
| `4`  | Aggregate preflight or repository operation failed | Repair the reported profile/category or repository state, then rerun |

Other bootstrap CLI failures use their normal typed exit codes and redacted
stderr error path. A successful JSON parse is not enough: use the process exit
status as the aggregate success signal.

## Failure And Recovery

The service completes aggregate local preflight before any profile push. A
preflight failure reports the invalid profile with its redacted category and
reports all other profile entries as `aggregate_preflight_blocked`; no remote
tree was compared or modified.

After preflight, profile publication is sequential and independently locked.
One Git failure does not stop later profiles from being attempted. A push race
gets one fetch-and-rebuild retry. A matching-tree remote descendant is accepted;
a second race failure is reported as `push_race_exhausted`.

For a repair handoff, give the repair task only the failed profile and its
redacted category. Correct the local authoritative profile or the owning
engine/environment, then run the dry-run command followed by the real command.
Accept the repair only when the aggregate exits `0` and the repaired profile is
`changed` or `unchanged`. Do not use remote content to repair an existing local
profile.

## Future Handoff

The two-hour profile-sync cron handoff and its private Slack channel ID are
future `hermes-home` Task 7 work. They are not deployed by the current
bootstrap or this operations change. Any future root-owned wrapper must invoke
the same aggregate command and must remain local-to-remote for existing named
profiles.

## Verification Gate

Run the focused test gate for changes to the bootstrap implementation or these
operations docs:

```text
task hermes:bootstrap:test
```

The suite covers four-profile bootstrap sequencing, first-install seeding,
invalid-existing failure without fallback, aggregate preflight, exact remote
tree deletion, local immutability, retry behavior, compact JSON, exit status,
and redaction.
