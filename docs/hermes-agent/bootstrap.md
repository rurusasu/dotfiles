# Hermes Bootstrap Operations

Hermes uses one container-owned bootstrap on every supported host. The host
adapter supplies prerequisites and secrets; it does not directly write Hermes
config, profiles, repositories, or `.env` files.

## Run Bootstrap

Prerequisites are a running Docker daemon, Docker Compose, an authenticated
1Password CLI (`op`), access to the seven configured items, and access to the
declared private GitHub repositories. Unix requires native `bash`, `jq`,
`curl`, `docker`, and `op`. The Unix adapter uses `curl` for bounded gateway
readiness checks. Windows requires `pwsh`, Docker Desktop native `docker` and
Compose plugin, and authenticated native `op.exe`; the focused adapter does
not route these commands through WSL.

For a focused full bootstrap on any supported host, run:

```text
task hermes:bootstrap
```

On Unix, the task sources `scripts/sh/hermes-agent.sh` and invokes its Docker
adapter. On Windows, it runs
`pwsh -NoProfile -File scripts/powershell/hermes-bootstrap.ps1`. Both adapters
validate Compose, build `hermes` and `hermes-bootstrap`, run the container
bootstrap, and recreate the stack only after success. The full installer chains
remain:

```text
install.sh -> OS installer -> shell adapter (scripts/sh/hermes-agent.sh) -> hermes-bootstrap container -> compose up
install.cmd -> install.ps1 -> install.admin.ps1 -> HermesAgentHandler -> PowerShell adapter (HermesBootstrap.ps1) -> hermes-bootstrap container -> compose up
```

`HermesAgentHandler` is Phase `2`, order `56`, and
`RequiresAdmin = false`. It must stay in the user context so native `op.exe`
can use 1Password desktop integration.

`task hermes:bootstrap` returns the selected focused adapter status; it neither
runs the full-machine installer nor hides a nonzero result.

## Data Flow

```text
host adapter
  -> request the non-secret secret plan
  -> fetch seven full 1Password item JSON objects
  -> stream header + seven item records + end as NDJSON
  -> docker compose run --rm --no-deps -T hermes-bootstrap apply
  -> load manifest and recover any crash journal
  -> validate payload, credentials, and source access
  -> publish existing profiles, stage sources, and sync shared remotes
  -> transactional install under /opt/data
  -> docker compose up -d --force-recreate only after success
```

Each item record embeds the full `op item get <title> --account
my.1password.com --vault openclaw --format json` object. The stdin stream is
never stored, logged, or placed in a process argument. All seven items are
mandatory: `Hermes Agent Dashboard`, `GitHubUsedOpenClawPAT`,
`SlackBot-OpenClaw`, `SlackBot-Rick`, `SlackBot-Hoffman`,
`SlackBot-Risarisa`, and `SlackBot-Nancy` in account `my.1password.com`, vault
`openclaw`.

Required labels are `username` or `user name` and `password` for the dashboard;
`credential`, `token`, `PAT`, or `password` for the GitHub item; and
`SLACK_BOT_TOKEN`/`bot_token`/`bot token`,
`SLACK_APP_TOKEN`/`app_level_token`/`app token`/`app-level token`, and
`SLACK_ALLOWED_USERS`/`allowed_users`/`allowed users`/`allowFrom`/`allow_from`
for each Slack item. Bootstrap validates GitHub authentication and all remote
access after crash-journal recovery and before it begins new staging or
transaction writes. Recovery may restore or delete previously journaled managed
paths before secrets and credentials are validated. Managed `.env` keys include
the three GitHub aliases, dashboard username/hash/signing secret, and profile
Slack credentials; root also owns `API_SERVER_KEY`, which is removed from named
profile `.env` files.

## Runtime `gh` Authentication

`docker/hermes-agent/gh-wrapper.sh` resolves credentials in this order:

1. an existing `GH_TOKEN` process variable;
2. `${HERMES_HOME}/.env` for the active root or named profile;
3. `/opt/data/.env` as the shared root fallback.

It maps `GITHUB_PERSONAL_ACCESS_TOKEN` or `GITHUB_TOKEN` to `GH_TOKEN` and then
executes `/usr/bin/gh`. It does not run `gh auth login` or create a separate
`hosts.yml`. If no token is available, rerun bootstrap after repairing the
configured GitHub item. Hermes propagates the active profile's `HERMES_HOME`,
so the same wrapper works for root and named profiles.

## Sync Shared Lifelog

Lifelog remains a normal read-write shared Git repository, not a named-profile
exact mirror. The manifest assigns `sync_owner: default`; all profiles use the
same canonical checkout at `/opt/data/shared/lifelog`.

The current owner operation is:

```text
hermes-bootstrap sync-repository lifelog
```

From the dotfiles repository, an operator may invoke the same command through
Compose:

```text
docker compose -f docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap sync-repository lifelog
```

It resolves the token as process `GH_TOKEN`, then the safe active
`${HERMES_HOME}/.env`, then `/opt/data/.env`. Env files are parsed as data and
never executed; unsafe, duplicate, symlinked, hard-linked, or special-file
sources fail closed. The command validates the canonical repository, acquires
`/opt/data/locks/repositories/lifelog.lock`, and runs the ordinary read-write
commit/rebase/push workflow. Its success JSON reports `status`, `name`,
`commit`, and `pushed`.

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
A declared `distribution_owned` directory with no publishable regular-file
descendant is invalid and fails preflight with `empty_owned_directory`. A nested
empty directory beneath a nonempty declared owned root is omitted from the Git
projection because Git cannot represent it.

Hermes installs an exactly top-level declared `.env.template` as
`.env.EXAMPLE`. Snapshotting reverses only that mapping: it reads the safe
installed `.env.EXAMPLE` bytes and publishes them as `.env.template`, while the
canonical manifest and `.gitignore` retain the declared source name. Missing,
symbolic-link, non-regular, concurrently replaced, or secret-like installed
content fails preflight. `.env`, nested `.env.template`, explicitly owned
`.env.EXAMPLE`, and every other `.env*` path remain invalid. The pre-transaction
snapshot revalidation repeats the same mapping, so a late `.env.EXAMPLE` change
fails with `local_profile_changed`.

The configured manifest currently includes `rick`, `hoffman`, `risarisa`, and
`nancy`. Do not use an obsolete three-profile list in a procedure or test.
Asset ownership is not hard-coded by profile name: avatar and portfolio files
are included only when that profile's valid local manifest declares `assets`.
Task 5 fixtures cover declared assets for Rick, Hoffman, and Nancy and no
`assets` declaration for RisaRisa.

## First Install And Bootstrap Ordering

Bootstrap validates credentials and repository access, snapshots all existing
profiles, and completes their exact local-to-remote publication before staging.
It then stages the remote-authoritative root distribution; stages every profile
in manifest order using the exact returned commit for an existing profile or
the configured branch for a truly missing profile; runs
`validate_chrome_mcp_sources` over the staged root and profiles; synchronizes
shared repositories, including lifelog; and only then calls
`Transaction.begin`. Inside the transaction it applies root, named profiles in
manifest order, shared working trees, and managed environment files. Existing
named-profile publication has already completed before the staged Chrome gate.
If that validation fails, its reported remote commits remain valid and are not
rolled back; bootstrap fails before shared-repository synchronization or local
transaction mutation.

`apply` holds the canonical nonblocking `EngineLock` at
`/opt/data/locks/bootstrap-engine.lock` from before crash-journal recovery
through transaction and private-scratch cleanup. The same cooperative lock
wraps `sync-profiles` and `sync-repository`; repository locks are subordinate
to it. Read-only `secret-plan` and `validate` do not acquire it. Lock
contention fails through the redacted repository error boundary.

After root/profile staging, staged Chrome validation, and shared-repository
synchronization, `apply` recreates every profile snapshot before
`Transaction.begin`. It compares the target set, canonical manifests,
`.gitignore`, path inventory, regular-file modes and sizes, per-file SHA-256
values, and aggregate digest. Any drift, including a missing target created
during apply, fails with `local_profile_changed` before local distribution or
environment mutation. Remote commits from the original immutable snapshot
remain valid. A final named-profile apply guard permits remote installation
only for a missing target; an existing target that differs from the staged
local projection fails closed and is never force-overwritten.

A target directory that is truly absent is seeded from its configured remote
for the first official Hermes install. An existing malformed or incomplete
profile is not absent: bootstrap fails before its transaction and never falls
back to a remote overwrite.

If synchronization fails, bootstrap does not begin its local transaction or
restart Hermes. There are two public diagnostics:

- Snapshot preflight can fail before a `profile_report` is created. `apply`
  writes `profile snapshot rejected (<category>)` to stderr, without a profile
  name or report. Standalone `sync-profiles --dry-run` identifies the invalid
  profile and category in its JSON.
- A nonzero post-preflight publication report writes
  `named profile repository sync failed: <failed names>` to stderr. The Python
  exception can retain the report internally.

Every `named profile repository sync failed: <failed names>` message requires
the guarded profile, outer-bootstrap, and private shared-repository stage
artifact inventories in the cleanup runbook before any retry or closure. The
CLI-hidden category could be `cleanup_failed`; neither an expected push
diagnosis nor a later successful sync excludes that possibility.

Snapshot-preflight rejection is a different trigger. Publication has not begun,
and `profile snapshot rejected (<category>)` exposes its category. If the inner
category is `cleanup_failed` but that exact message reaches the CLI, the final
outer apply scratch cleanup did not fail; otherwise the outer cleanup error
would replace it with `could not clean bootstrap staging resources`. That
exact snapshot message alone does not trigger the direct-child publication
inventory because publication resources were not created. A non-cleanup
snapshot category likewise does not activate the post-publication inventory
trigger.

`could not clean bootstrap staging resources` is itself an indeterminate
cleanup trigger. Final outer cleanup can replace a snapshot-preflight,
publication, staging, transaction, validation, or other primary failure. If a
profile report had already been created, it can remain attached internally, but
the CLI exposes neither that report nor the replaced primary failure. Before
retry or closure, inventory both the profile scratch prefixes and the outer
`.hermes-bootstrap-*` prefix below, plus private
`/opt/data/shared/.hermes-repository-*` stages. A candidate or indeterminate
determination activates the same full-window quiescent quarantine procedure; a
later successful command does not waive any inventory.

Once synchronization has created `profile_report`, later staging, transaction,
installed-layout validation, cleanup, or rollback failures can also retain that
report on the internal Python exception. The CLI never serializes this
attribute. By default every failed `apply` has empty stdout and exactly one safe
error message on stderr. With `HERMES_BOOTSTRAP_DEBUG=1`, a sanitized traceback
from the public CLI boundary may follow that message; it contains neither
tokens nor the raw internal exception graph.

Use dry-run only for aggregate preflight and diff inspection. It never pushes,
so a changed entry reports category `dry_run`; it cannot reproduce
`push_rejected`, `push_race_exhausted`, or another push-only failure. To obtain
a push-only category, run standalone real `sync-profiles` and inspect its JSON.
The real aggregate processes every manifest profile and may push changes for
profiles other than the original failure. Successful pushes remain valid and
cannot be rolled back; a subsequent run reports them as `unchanged` when the
remote tree matches the same local snapshot.

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

For `unchanged`, `commit` is the current remote head, `snapshot` is the local
snapshot digest, all diff arrays are empty, and the category/message are
`unchanged` / `profile snapshot already published`. A changed dry run also
reports the current remote head because it creates no commit; it includes the
actual diff with `dry_run` / `profile snapshot changes detected`. A changed
real run reports the resulting remote commit and uses
`published` / `profile snapshot published`.

An ordinary per-profile Git or publication failure after snapshot preparation
does not replace other completed profile results; their available snapshots,
commits, and diffs remain in the aggregate. The failed entry retains its
profile snapshot digest, while an unavailable commit is `null` and unavailable
diff arrays are empty. Credential failures and aggregate pre-snapshot failures,
including a missing or malformed profile, report an empty snapshot for every
profile.

Final top-level snapshot scratch cleanup is a separate aggregate failure. If it
fails after profile processing, the command replaces all completed results
with `cleanup_failed` entries whose snapshots are empty, commits are `null`,
and diff arrays are empty. Standalone `sync-profiles` never installs a missing
target: it exits `4` with a failed aggregate. Only bootstrap `apply` uses the
missing-target first-install exception.

| Exit | Meaning                                          | Operator action                                                      |
| ---- | ------------------------------------------------ | -------------------------------------------------------------------- |
| `0`  | Every profile is `changed` or `unchanged`        | Continue; cleanup recovery uses the quiescent quarantine runbook     |
| `3`  | Credentials unavailable                          | Repair the runtime GitHub credential source, then rerun              |
| `4`  | Missing target, preflight, or repository failure | Repair the reported profile/category or repository state, then rerun |

Invalid arguments exit `2`, manifest validation exits `8`, and unexpected
command failures exit `6`. Those errors use the safe stderr path and do not
emit a `sync-profiles` JSON document. A successful JSON parse is not enough:
after a normal complete stdout write, use the report's process exit status as
the aggregate success signal. The existing BrokenPipe contract is an exception:
if stdout closes while the JSON is written, the CLI returns `0` even for a
failure report. Automation must consume stdout through EOF and must not
interpret an early-closing pipe's `0` as successful synchronization.

## Failure And Recovery

The service completes aggregate local preflight before any profile push. A
preflight failure reports the invalid profile with its redacted category and
reports all other profile entries as `aggregate_preflight_blocked`; no remote
tree was compared or modified.

After preflight, profile publication is sequential and independently locked.
One Git failure does not stop later profiles from being attempted. A push race
gets one fetch-and-rebuild retry. A matching-tree remote descendant is accepted;
a second race failure is reported as `push_race_exhausted`.

For a snapshot-preflight repair handoff, take the failed profile and redacted
category from standalone dry-run JSON. Correct the local authoritative profile
or its owning engine/environment, then rerun dry-run until aggregate preflight
is green. Run real `sync-profiles` next. If publication fails, take the failed
profile and push-only category from that real JSON report; do not infer it from
dry-run. The real aggregate can publish other profiles, and successful pushes
are not rolled back. Accept the repair only when the real aggregate exits `0`
and the repaired profile is `changed` or `unchanged`. Do not use remote content
to repair an existing local profile.

### Bootstrap Scratch Cleanup Recovery

A `cleanup_failed` result is not closed by a later successful run alone. Each
invocation cleans only artifacts it created and still tracks; it does not scan
for private artifacts left by an earlier invocation. The engine lock serializes
cooperating bootstrap commands, but a one-time process or lock check is not a
safe cleanup proof by itself.

The supported threat model covers malformed remotes, malformed or concurrently
edited local content, crashes, cooperating concurrent bootstrap commands,
symlinks, special files, unexpected mounts, and accidental pathname
replacement. It trusts the kernel, filesystem, container runtime, and bootstrap
execution context. An actively malicious same-UID process that deliberately
bypasses `EngineLock` is outside this model; cleanup does not claim an atomic
identity-check-and-delete guarantee against that actor.

The full procedure is mandatory for an explicit standalone `cleanup_failed`
report. A post-preflight apply publication message has a hidden category, and
`could not clean bootstrap staging resources` can replace an earlier hidden
profile report or another primary failure. Both messages must complete the
unified quiescent inventory and decision steps below even when the suspected
cause is an ordinary push failure.

1. Establish one named maintenance owner. Stop and disable every launch path
   for the entire recovery window: the Hermes gateway and scheduler, any
   deployed profile-sync cron or scheduled task, bootstrap Compose runs, host
   installers and Taskfile entrypoints, and manual `apply`, `sync-profiles`, or
   `sync-repository` commands. Confirm existing runs have exited and no
   transaction or repository lock has an owner. Lock files may persist while
   unlocked. Do not re-enable any launcher until the final step; only the
   maintenance owner may run the controlled verification commands below.
2. From a maintenance environment that sees the same `/opt/data` mount
   namespace, inventory only direct children whose complete names match
   `.hermes-profile-snapshots-*`, `.hermes-profile-sync-*`, `askpass-*`, or
   `.hermes-bootstrap-*` under canonical `/opt/data`. Separately inventory only
   direct children of canonical `/opt/data/shared` whose complete names match
   `.hermes-repository-*`; `repositories.py` creates these private first-clone
   stages in the shared repository target's parent. Always inventory the
   profile-scratch, outer-bootstrap, and private shared-repository stage groups,
   even when the public error names only one phase. Separately inventory any
   prior `.hermes-profile-cleanup-quarantine-*` directory. An existing
   quarantine is unresolved recovery evidence: do not reuse or remove it; stop
   and escalate.
3. Inspect every candidate individually with no symlink following. Both
   `.hermes-profile-*` forms and `.hermes-bootstrap-*` must be real directories
   directly under canonical `/opt/data`, owned by the maintenance service
   UID/GID, with mode `0700` and the exact expected prefix. A
   `.hermes-repository-*` candidate must meet the same directory, owner, and
   mode checks directly under canonical `/opt/data/shared`. An `askpass-*`
   candidate must be a real regular file directly under `/opt/data`, with the
   same owner, mode `0700`, link count `1`, and exact prefix. Any unexpected
   path, descendant mount, type, owner, mode, link count, prefix, or location is
   an escalation, not a deletion candidate.
4. Capture an authoritative mount inventory for that maintenance namespace,
   such as Linux `/proc/self/mountinfo` or reliable mountpoint tooling. Compare
   its canonical mount targets against each canonical candidate subtree.
   Reject a candidate if it or any descendant is a mountpoint or bind mount.
   `find -xdev` is not a mountpoint detector. If canonicalization, mount
   inventory, or subtree comparison is unavailable or ambiguous, do not remove
   anything; preserve evidence and escalate.
5. Record the decision for all candidate groups before any retry. For a
   hidden-category apply publication failure, reliably empty profile and outer
   inventories, an empty private shared-repository stage inventory, and
   complete mount determination return to ordinary push-failure recovery in
   step 8 without creating quarantine. An explicit standalone `cleanup_failed`,
   or an outer
   `could not clean bootstrap staging resources`, keeps its cleanup diagnosis
   even when all candidate inventories are empty and proceeds to controlled
   verification only after its owning cleanup fault is repaired. If any
   candidate exists, activate the quarantine path in steps 6 and 7. If any
   determination is unavailable, the full recovery path is active but cannot
   safely proceed; preserve evidence and escalate. A later dry-run or real
   aggregate exit `0` never substitutes for this pre-retry inventory because
   old artifacts are not revisited.
6. Create a unique `.hermes-profile-cleanup-quarantine-<incident-id>` directory
   directly under `/opt/data`. Verify that it is owner-created, non-symlink,
   mode `0700`, contains no mountpoint, and has the same filesystem device as
   every candidate. Revalidate each candidate immediately before moving it,
   then atomically rename each exact candidate into quarantine without using
   globs. Any rename failure, including `EXDEV` or `EBUSY`, aborts the operation;
   leave the quarantine untouched and escalate.
7. After every candidate is isolated, refresh the mount inventory and recheck
   the quarantine and every descendant. Confirm the quarantined entries match
   the reviewed candidate set and remain mount-free. Only then remove the
   quarantine with a no-follow, type-aware procedure that refuses mount
   crossings. Do not use blind `rm -rf`, wildcard `rm`, a broad `.hermes-*`
   pattern, or `find -delete`.
8. While all ordinary launch paths remain disabled, require zero direct
   profile-scratch and outer-bootstrap names under `/opt/data`, zero private
   `.hermes-repository-*` stage names under `/opt/data/shared`, zero quarantine
   names, and no related mount issue. The maintenance owner then runs
   standalone dry-run and real `sync-profiles`, consumes both JSON reports
   completely, and requires both aggregates to exit `0` with the repaired
   profile `changed` or `unchanged`. Refresh all candidate groups plus the
   quarantine and mount inventories once more and require them to remain clean.
9. Record the evidence and only then re-enable the gateway, scheduler,
   `profile-local-sync` when its ordered `hermes-home` dependency branch has
   merged and the root distribution has been applied, installers, and other
   launch paths.

Cleanup recovery is accepted only when the entire quiescent procedure,
quarantine removal, dry-run/real verification, and final zero profile-scratch,
outer-bootstrap, private shared-repository stage, quarantine, and mount
inventories succeed. A later aggregate `0` without this evidence does not close
the incident.

## Transaction And Rollback

After manifest loading and before reading or validating a new secret payload,
`apply` calls `Transaction.recover_if_needed` for journals under
`/opt/data/.bootstrap/transactions/`. A single-writer transaction lock prevents
two local applies from mutating managed paths concurrently. Recovery may restore
or remove previously journaled managed paths; it is intentionally not covered
by validation-before-new-write claims.

After recovery completes, credential validation, profile publication,
root/profile staging, staged `validate_chrome_mcp_sources`, and shared remote
synchronization finish before `Transaction.begin` because remote pushes cannot
be rolled back. Existing named-profile publication is already complete when
the staged Chrome gate runs and remains valid if that gate fails. Inside the
new transaction, bootstrap snapshots root-owned paths, named profile targets,
shared working-tree publication, deprecated-path cleanup, and managed `.env`
files before replacement. Environment files use atomic rename and mode `0600`,
preserve unmanaged keys, and replace only managed keys.

If apply or final validation fails, bootstrap restores ready journal entries in
reverse order and leaves the gateway stopped. A rollback failure exits `7`; do
not delete its journal or manually overwrite managed paths until the failure is
understood. A normal failed apply can be rerun after repair, and the next apply
recovers any interrupted active journal before beginning new work. Remote
profile or lifelog pushes completed before the transaction remain valid and are
not reversed.

The gateway API binds to `0.0.0.0:8642` inside the container, while Compose
publishes it only on host loopback. Hermes refuses to start that API without the
managed strong `API_SERVER_KEY`.

## Repository Locks And Diagnostics

Shared repository commands use
`/opt/data/locks/repositories/<name>.lock`; profile publication uses
`/opt/data/locks/repositories/profile-<name>.lock`. Lock acquisition is
nonblocking. For lifelog migration/publication, bootstrap reacquires the same
repository lock and keeps it while publishing the verified working tree and
removing the legacy path. After confirming the competing process has exited,
rerun the same command.

Git status, index, staged-path, and unpushed-history inspection is bounded to
8 MiB per command and fails closed above that limit. Shared repository
synchronization rejects credential artifacts, runtime state, databases, and
nested Git repositories, while allowing ordinary knowledge filenames such as
`authentication-guide.md` and the repository-root `.env.example`.
Authenticated operations use root-owned `/usr/bin/git`, a short-lived
`GIT_ASKPASS` file, and the system default `PATH`; credentials are not stored in
remote URLs.

## Migration And Conflicts

- A legacy real checkout at `/opt/data/core/lifelog` is copied to private
  staging, validated, and transactionally published at
  `/opt/data/shared/lifelog`. The legacy path is removed only after it has been
  snapshotted.
- An empty legacy directory or compatibility symlink from an older bootstrap is
  removed transactionally.
- If both old and canonical lifelog paths contain real data, bootstrap exits
  `5`. It does not merge, delete, or choose between them; reconcile or back up
  one path explicitly, then rerun.
- Existing root files are replaced only when declared by
  `root-distribution.yaml`. Existing named profiles follow the local-authority
  rules above and are never repaired by forced remote replacement.
- Existing `.env` files preserve unmanaged keys. Repeat apply reuses a valid
  dashboard hash, signing secret, and bootstrap-issued root API key; invalid
  managed material is replaced, and named-profile API keys are removed.

## Complete Exit Codes

| Code | Meaning                                                                    | Operator action                                                                                                                                                                         |
| ---- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0`  | Success                                                                    | Continue; cleanup recovery uses the quiescent quarantine runbook                                                                                                                        |
| `1`  | Host secret-plan or payload production failed                              | Fix `op` or adapter input and rerun                                                                                                                                                     |
| `2`  | Invalid command arguments, payload, or managed env input                   | Correct input; no Compose restart                                                                                                                                                       |
| `3`  | Missing, invalid, or unauthorized credential                               | Repair 1Password or GitHub access                                                                                                                                                       |
| `4`  | Repository access, identity, lock, profile preflight, or sync failure      | Repair the reported repository/profile state                                                                                                                                            |
| `5`  | Migration conflict                                                         | Reconcile the named old/new paths manually                                                                                                                                              |
| `6`  | Apply, cleanup, or unexpected command failure                              | Inspect safe diagnostics and rerun                                                                                                                                                      |
| `7`  | Rollback failure                                                           | Preserve the journal and inspect managed paths before retrying                                                                                                                          |
| `8`  | Manifest, staged Chrome source-contract, or final layout validation failed | Repair the manifest, owning root/profile source, or final layout; for an existing local-authoritative profile, repair local declarative config and rerun the documented sync/apply flow |

`sync-profiles` uses its JSON route only for handled exits `0`, `3`, and `4`.
Its argument error `2`, manifest validation error `8`, and unexpected error `6`
use stderr without a result document. Failed `apply` likewise uses stderr.
Snapshot-preflight rejection occurs before a profile report exists. After
synchronization creates one, publication, staging, transaction, validation,
cleanup, and rollback failures may retain it on the internal Python exception.
The CLI does not serialize that report. Its default output is the single safe
error described above; debug mode may append only the sanitized public-boundary
traceback.

## Future Handoff

The two-hour profile-sync cron handoff and its private Slack channel ID are
future `hermes-home` Task 7 work. They are not deployed by the current
bootstrap or this operations change. Any future root-owned wrapper must invoke
the same aggregate command and must remain local-to-remote for existing named
profiles.

## Source Validation Gate

Changes under `docker/hermes-agent/`, or to `Taskfile.yml`,
`.pre-commit-config.yaml`, or the Hermes bootstrap workflow itself, run
`task hermes:bootstrap:test` through the local `hermes-bootstrap-tests`
pre-commit hook. Pull requests run the same pinned Docker stage and the `gh`
wrapper security suite in the `Hermes Bootstrap Tests` workflow. Both paths
also run the same host-side profile-sync provenance verifier. Locally it reads
the sibling `hermes-home-profile-sync` worktree; GitHub Actions checks out
`rurusasu/hermes-home` at the validated provenance commit first. That private
checkout requires the `HERMES_HOME_READ_TOKEN` repository secret with read-only
Contents access, and the provenance commit must already exist on the remote.
The verifier requires clean tracked source and fixture paths, exact bytes, Git
blob IDs, SHA-256, and committed tree mode `100755`. Task 5 integration
coverage is the publication gate for aggregate preflight, exact-tree deletion,
local immutability, missing-only bootstrap install, continuation, retry, and
result serialization.

Named-profile default branches are exact mirrors. A real sync deletes
repository-local `.github` workflows, pre-commit configuration, validators,
tests, and README files because they are outside the local declarative
allowlist. Therefore named-profile mirrors, including Nancy, are not governed
by a repository-local `fast`/`full` or GitHub Actions validator contract.
Their replacement is:

- runtime aggregate snapshot preflight and `sync-profiles` result handling;
- dotfiles engine pre-commit and `Hermes Bootstrap Tests` GitHub Actions; and
- the pinned unit/integration gate `task hermes:bootstrap:test`.

The scoped [Distribution Validation](distribution-validation-design.md)
contract remains normative for the remote-authoritative `hermes-home` root and
only those source repositories explicitly declared to retain its workflow,
pre-commit, and validator files. A profile manifest entry does not opt a mirror
into that contract. For an in-scope source repository, validator exits remain
`0` pass, `1` validation failure, `2` prerequisite blocked as `ENV_BLOCKED`,
and `3` validator internal failure as `INTERNAL_ERROR`. Exact-head evidence is
required, and automated repair remains limited to two rounds for the same
failed check set; failure after two rounds is `FIX_FAILED`, while an
`ENV_BLOCKED` result does not consume a repair round.

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
