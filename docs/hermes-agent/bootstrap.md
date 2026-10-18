# Hermes Bootstrap Operations

On macOS and Linux/WSL, the pinned `hermes-agent` flake and Home Manager module
manage the Hermes CLI and native gateway service. On Windows, the installer applies that Nix-managed runtime in the configured NixOS WSL distribution. The
Nix module also installs `hermes-bootstrap` and a manifest rooted at
`~/.hermes`; `task hermes:sync` streams 1Password item data to that native
bootstrap and synchronizes profiles and shared repositories.

On macOS, the CLI and gateway use the official complete bundle pinned by Nix;
see [Desktop installation](desktop.md#desktop-installation-and-launch).
Bootstrap uses the same bundled Python, dependencies and profile API as the CLI.
Profile ownership follows the current machine-local PM layout described in
[Home/Profile Layout](profile-home-layout.md#machine-local-dependencies).

On Linux, the runtime uses the official upstream `packages.<system>.default` output with
the complete dependency graph from that pinned Hermes revision. Its nixpkgs,
flake-parts, and Home Manager inputs do not follow this repository's inputs;
runtime dependencies are not overridden or replaced with a reduced variant.
The consuming Home Manager module still manages our service and profile settings.
This follows the [official Nix setup](https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup).
An unchanged derivation can reuse a matching binary from a configured trusted
cache, but a Nix flake is not a guarantee that every pinned output is cached.
Missing binaries still require a source build; no new cache is implicitly trusted.

Docker is not used for the Hermes Agent runtime or its bootstrap. Docker browser
and MCP sidecars remain separate services. The old `hermes-data` volume is not
automatically copied, modified, or removed; review the one-time migration below
before moving any existing state into `~/.hermes`.

The native service and bootstrap use the host's `~/.hermes` directory. Enabling
the native service does not migrate, modify, or remove an existing Docker volume
or its state.
Moving data between these runtimes is an operator-led migration: take and
verify an explicit backup first, then decide how to resolve path conflicts
before copying anything. No automatic merge or winner is defined.

### One-time Docker-volume migration

Run this only in a Linux/WSL shell whose Docker CLI can access the old volume.
First identify its exact name with `docker volume ls` (Compose commonly prefixes
`hermes-data` with the project name); do not assume the name. Stop the legacy
`hermes` gateway with its existing Compose project before exporting so its
SQLite and session files are quiescent. Do not run `docker volume rm`.

```bash
set -euo pipefail
umask 077
volume='REPLACE_WITH_THE_EXACT_VOLUME_NAME'
export_dir="$HOME/.local/share/hermes-migration"
install -d -m 700 "$export_dir"
docker run --rm \
  --mount "type=volume,src=$volume,dst=/source,readonly" \
  --mount "type=bind,src=$export_dir,dst=/export" \
  busybox:1.36.1 sh -c 'tar -czf /export/hermes-data.tar.gz -C /source .'
chmod 600 "$export_dir/hermes-data.tar.gz"
tar -tzf "$export_dir/hermes-data.tar.gz" >/dev/null

stage="$(mktemp -d "$HOME/.hermes-migration.XXXXXX")"
chmod 700 "$stage"
tar -xzf "$export_dir/hermes-data.tar.gz" -C "$stage"
```

Review the staged tree before activation. If `~/.hermes` does not exist, move
the reviewed staging directory to that path and make the current WSL user its
owner. If it already exists, do not overlay it: compare the two trees and merge
conflicts deliberately, especially `.env`, provider credentials, profiles, and
session databases. The original Docker volume and the mode-`0600` archive remain
available for rollback; retain them until the Nix-managed CLI and gateway have
been verified. The Windows installer and Nix activation never perform this
copy or remove the old volume automatically.

Hermes の組み込み 1Password 連携と `op` CLI の利用手順は、[Hermes Agent で 1Password を使う](./onepassword.md)を参照してください。

## Run Bootstrap

### Ownership and removal boundary

Nix owns the Hermes package, native gateway, plugin installation and root
`services.hermes-agent.settings`. The bootstrap is not an installer: it owns
runtime secret updates, mutable profile distributions and shared repository sync.
Its CLI uses the existing package entrypoint (`python -P -m hermes_bootstrap`),
with the local package before upstream on `PYTHONPATH`; no separate CLI Python
file or unused upstream source patch is needed.

Chrome, X API, Calendar and Gmail share one MCP configuration writer.
LCM uses one pure merge for both ordinary and newly created profile directories.
Individual configuration files use private temporary files and atomic
replacement, followed by final installed-layout validation.

Removing the remaining bootstrap requires replacements for all three runtime
responsibilities above, including safe retries, unmanaged-file preservation and
every named or locally added profile. The pinned upstream Home Manager merge
targets only the root config and replaces lists, so copying complete profile
configs with `hermesHomeFiles` is not an equivalent migration. Secrets must
remain runtime-only and must not be embedded in Nix store outputs.

The native bootstrap requires the Nix-managed Hermes commands, `op`, `jq`, and
access to the 1Password Service Account item and declared GitHub repositories.
Home Manager installs Hermes, the native gateway, `hermes-bootstrap`, Node.js
for the pinned Calendar/Gmail MCP launchers, and the manifest under
`~/.hermes`. Windows runs the same flow inside the configured NixOS WSL
distribution.

```text
task hermes:bootstrap  # activate Nix/Home Manager, then synchronize
task hermes:sync       # re-apply secrets, profiles, and repositories
```

The native script reads the Service Account token into process memory, fetches
the planned 1Password items, and streams the JSON payload directly to
`hermes-bootstrap apply` over stdin. Secrets are not written to `.op.env`, a
temporary file, or command arguments. The apply synchronizes
profile distributions and shared repositories, installs private credentials,
and reconciles every managed Hermes profile before the gateway restarts.

Browser and X API MCP remain optional Docker sidecars, published only on
loopback for native Hermes. They are not a Hermes Agent backend. No Docker Hermes gateway/bootstrap service or backend
image is used.

The standard installer paths are:

```text
install.sh -> OS installer -> task hermes:bootstrap -> Nix/Home Manager runtime + native sync
install.cmd -> task nrs -> NixOS WSL runtime + native sync
```

The Windows installer uses the public `nrs` task to apply Nix/Home Manager in NixOS WSL. The WSL E2E verifies the native Hermes service and CLI as the configured Linux user.
Hermes is installed only inside NixOS; Windows has no separate Hermes handler.
If the rebuild or native service validation fails, installation fails
instead of falling back to Docker. An old Docker volume is not copied, modified,
or deleted automatically; follow the one-time migration instructions only if
you explicitly need data from it.

## Data Flow

```text
native host wrapper
  -> read 1Password Service Account token without persisting it
  -> request the manifest-derived secret plan
  -> fetch the declared 1Password items
  -> stream header + item records + end as NDJSON over stdin
  -> hermes-bootstrap apply
  -> refuse unresolved transaction data from an earlier implementation
  -> validate payload, credentials, and source access
  -> synchronize profile distributions and shared repositories
  -> reconcile root/profile config, credentials, and managed environment
  -> validate the installed layout under ~/.hermes
  -> restart the Nix-managed native gateway
```

Each item record embeds the full `op item get <title> --account
my.1password.com --vault openclaw --format json` object. The stdin stream is
never stored, logged, or placed in a process argument. Bootstrap reads only
`GitHubUsedOpenClawPAT` and `Google Calendar MCP` from account
`my.1password.com`, vault `openclaw`. Other manifest items supply runtime
1Password references rather than raw bootstrap payload values.

Required labels are `credential`, `token`, `PAT`, or `password` for the GitHub
item. The Calendar item requires `oauth_credentials_json` and
`tokens_json`; bootstrap installs both as mode `0600` files in the shared
`${HERMES_HOME}/google-calendar-mcp` directory, independently of named-profile
synchronization.

Gmail reuses the Calendar OAuth client in the shared
`${HERMES_HOME}/google-gmail-mcp` directory. Its host-local `credentials.json` is
preserved across bootstrap runs and shared by all profiles; it is not added to
the 1Password item plan.

Bootstrap checks source access through the Git fetch used for staging, before
managed-path writes. It does not create, read, merge, or
delete runtime `.env` files. Existing files remain user data. Dashboard password
hashes, signing secrets, and API keys are not generated by bootstrap.

Each managed config contains native `secrets.onepassword.env` references for
GitHub, xAI, and the profile's Discord credentials. The runtime resolves these
through an authenticated 1Password CLI; the Nix bootstrap wrapper supplies its
absolute executable path. Discord bot mentions use the non-secret
`platforms.discord.allow_bots: mentions` setting in each applicable config.

The seven profile-named items keep service credentials in separate sections.
Discord uses `Discord/bot_token` and `Discord/allowed_users`; additional
services must use their own sections rather than service-specific item names.
The retained Slack credentials use `Slack/bot_token`,
`Slack/app_level_token`, and `Slack/allowed_users`. The current bootstrap
consumes only the `Discord` section for messaging.

## Runtime `gh` Authentication

The native profile sync resolves repository credentials in this order:

1. a nonempty `GH_TOKEN`, `GITHUB_TOKEN`, or `GITHUB_PERSONAL_ACCESS_TOKEN`
   process variable, in that order;
2. the manifest's GitHub credential reference, read directly with `op read`.

The token is passed only to the scoped Git operation and is not written into
Git configuration, an `.env` file, or a separate `hosts.yml`. If no token is
available, repair the configured GitHub item and 1Password CLI authentication,
then rerun the failed command.

## Sync Shared Lifelog

Lifelog remains a normal read-write shared Git repository, not a named-profile
exact mirror. All profiles use the same canonical checkout at
`${HERMES_HOME}/shared/lifelog`, with the shared engine lock serializing updates.
Shared repository declarations contain only a name, source, branch, and target;
there is no read-only mode, pinned shared commit, or sync-owner metadata.

The native owner operation is:

```text
task hermes:repository:sync
```

It uses the same process-variable and 1Password lookup as profile sync, without
reading `.env` files. The command acquires the engine lock, validates the
canonical repository, and runs the ordinary read-write
commit/rebase/push workflow. Its success JSON reports `status`, `name`,
`commit`, and `pushed`.

The successful bootstrap JSON contains `status: "applied"`, the six profile
names, `repositories: ["lifelog"]`, and `profile_sync`. `profile_sync` maps
each named profile to `preserved` or `installed`; `installed` is only the
truly missing first-install case. Existing profile publication is explicit:
run `sync-profiles` separately.

## Sync Existing Named Profiles

Use the aggregate profile command before and after a local declarative repair:

```text
task hermes:profiles:sync -- --dry-run
task hermes:profiles:sync
```

It processes every profile declared in
`nix/modules/ai_agents/hermes/manifest.yaml` in manifest order. Do not replace
these commands with a clone or checkout inside a profile home.

For every existing valid named profile, the local `distribution.yaml` and
`distribution_owned` allowlist are authoritative. The service creates a private
snapshot, projects it into a temporary Git repository, and pushes a normal
fast-forward update. Existing profiles are preserved during bootstrap; only
missing profiles are installed through the official Hermes distribution API.
The profile home itself stays non-Git and both dry runs and real sync preserve
local bytes and modes.

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
canonical manifest and `.gitignore` retain the normalized source name. Path
normalization and the host filesystem determine spelling; bootstrap does not
add a separate raw-spelling or directory-entry-case requirement.
Missing, symbolic-link, hard-linked, non-regular, or secret-like installed
content fails preflight. `.env`, nested `.env.template`, explicitly owned
`.env.EXAMPLE`, and every other `.env*` path remain invalid. Snapshot creation
validates the allowlist and initial source types, scans file contents for
secrets, and preserves file contents and executable modes. The resulting Git
commit identifies a publication; bootstrap does not keep parallel per-file
checksums or recheck private snapshot contents for later modification. Avoid editing a profile
while bootstrap or profile synchronization is running.

The configured manifest currently includes `rick`, `hoffman`, `risarisa`,
`nancy`, `kuroda`, and `shiraishi`. Do not use an obsolete profile list in a
procedure or test.
Asset ownership is not hard-coded by profile name: avatar and portfolio files
are included only when that profile's valid local manifest declares `assets`.
Task 5 fixtures cover declared assets for Rick, Hoffman, and Nancy and no
`assets` declaration for RisaRisa, Kuroda, or Shiraishi.

## First Install And Bootstrap Ordering

Bootstrap validates the payload and existing profile layout, then stages the
root distribution and only truly missing profiles. Git fetch checks source access.
Existing named profiles remain
local-authoritative and are not published or replaced by `apply`; publication is
owned by the explicit `sync-profiles` command. Bootstrap then stages the
remote-authoritative root distribution, stages each missing profile in manifest
order using its configured branch and optional pinned commit, runs
`validate_chrome_mcp_sources` over the staged root and profiles, synchronizes
shared repositories including lifelog, and then applies root, missing profiles
in manifest order, shared working trees, and managed environment files. If a
staged validation fails, no profile publication has occurred and bootstrap fails
before shared-repository synchronization or managed-path writes.

`apply` holds the canonical nonblocking `EngineLock` at
`${HERMES_HOME}/locks/bootstrap-engine.lock` from before payload processing
through apply and private-scratch cleanup. The same cooperative lock
wraps `sync-profiles` and `sync-repository`. Read-only `secret-plan` and `validate`
do not acquire it. Lock
contention fails through the redacted repository error boundary.

The engine lock serializes cooperating bootstrap commands. It does not lock
out editors or other programs that modify profile files; stop those writes
while an operation runs. Source files are validated and copied once; bootstrap
does not repeat that validation before applying the staged content. A final
named-profile apply guard permits remote installation only for a missing target
and refuses an existing target.

A target directory that is truly absent is seeded from its configured remote
for the first official Hermes install. An existing malformed or incomplete
profile is not absent: bootstrap fails before managed-path writes and never
falls back to a remote overwrite.

If explicit synchronization fails, the report contains per-profile failures;
completed pushes remain valid because independent profile repositories are not
cross-repository atomic. Repair the failed local boundary and retry it. A
normal `apply` does not publish existing profiles and therefore does not fail
because a profile push failed. Public snapshot preparation and secret scanning
run only during `sync-profiles`. Standalone `sync-profiles --dry-run` identifies the invalid profile
and category in its JSON; a real `sync-profiles` run also reports publication
failures there.

Cleanup failures report `cleanup_failed` or
`could not clean bootstrap staging resources`. Each run cleans its own private
scratch directories; a later run does not clean artifacts left by an earlier
one. Follow [Scratch cleanup](#scratch-cleanup) before treating the failure as
resolved.

The `apply` command does not create a profile publication report because it
does not publish existing profiles. By default every failed `apply` has empty
stdout and exactly one safe error message on stderr. With
`HERMES_BOOTSTRAP_DEBUG=1`, a sanitized traceback may follow that message.
Internal exception chains and local variables are not printed. Bootstrap does
not erase exceptions or traceback locals retained by calling Python code.

Use dry-run only for aggregate preflight and diff inspection. It never pushes,
so a changed entry reports category `dry_run`; it cannot reproduce
`push_rejected` or another push-only failure. To obtain
a push-only category, run standalone real `sync-profiles` and inspect its JSON.
The real synchronizer also enforces each profile's `max_deleted_paths` limit;
an over-limit result uses category `deletion_limit_exceeded` and does not push.
The real aggregate processes every manifest profile and may push changes for
profiles other than the original failure. Successful pushes remain on the
remote; a subsequent run reports them as `unchanged` when the
remote tree matches the same local snapshot.

Root `hermes-home` remains remote-authoritative. `shared/lifelog` remains the
normal locked read-write Git repository. The local-first named-profile policy
does not change either model.

## Reading Results And Exit Codes

`sync-profiles` writes one JSON result line to stdout for both
success and handled sync failure; stderr is empty in those cases. The object
has `schema_version: 1`, `command: "sync-profiles"`, a boolean `dry_run`, an
aggregate `status`, and ordered `profiles` entries. Aggregate status is
`changed`, `unchanged`, or `failed`, not `success`.

Each profile entry includes `name`, `status`, `commit`, `added`,
`modified`, `deleted`, `paths`, `category`, and `message`. The three diff
fields and `paths` are arrays of relative paths; `paths` is the sorted combined
list. Treat `category` and `message` as redacted diagnostics.

For `unchanged`, `commit` is the current remote head, all diff arrays are empty,
and the category/message are
`unchanged` / `profile snapshot already published`. A changed dry run also
reports the current remote head because it creates no commit; it includes the
actual diff with `dry_run` / `profile snapshot changes detected`. A changed
real run reports the resulting remote commit and uses
`published` / `profile snapshot published`.

An ordinary per-profile Git or publication failure after snapshot preparation
does not replace other completed profile results; their commits and diffs remain
in the aggregate. An unavailable commit is `null` and unavailable diff arrays
are empty. Credential failures and aggregate preflight failures, including a
missing or malformed profile, report failed entries for every profile.

Final top-level snapshot scratch cleanup is a separate aggregate failure. If it
fails after profile processing, the command replaces all completed results
with `cleanup_failed` entries whose commits are `null`,
and diff arrays are empty. Standalone `sync-profiles` never installs a missing
target: it exits `4` with a failed aggregate. Only bootstrap `apply` uses the
missing-target first-install exception.

| Exit | Meaning                                          | Operator action                                                      |
| ---- | ------------------------------------------------ | -------------------------------------------------------------------- |
| `0`  | Every profile is `changed` or `unchanged`        | Continue                                                             |
| `3`  | Credentials unavailable                          | Repair the runtime GitHub credential source, then rerun              |
| `4`  | Missing target, preflight, or repository failure | Repair the reported profile/category or repository state, then rerun |

Invalid arguments exit `2`, manifest validation exits `8`, and unexpected
command failures exit `6`. Those errors use the safe stderr path and do not
emit a `sync-profiles` JSON document. A successful JSON parse is not enough:
after a normal complete stdout write, use the report's process exit status as
the aggregate success signal. If stdout closes while the JSON is written or
flushed, the CLI preserves that result code: successful synchronization returns
`0`, and a failed synchronization still returns its nonzero code. A broken pipe
inside command execution is reported as a command failure.

## Failure And Recovery

The service completes aggregate local preflight before any profile push. A
preflight failure reports the invalid profile with its redacted category and
reports all other profile entries as `aggregate_preflight_blocked`; no remote
tree was compared or modified.

After preflight, profile publication is sequential under the engine lock.
One Git failure does not stop later profiles from being attempted. Each profile
fetches once and attempts one non-force push. A rejected push or lost response
reports `push_rejected`; repair the cause and rerun `sync-profiles`. The next
run compares the remote tree with a fresh local snapshot, so an already
completed publication can report `unchanged`.

For a snapshot-preflight repair handoff, take the failed profile and redacted
category from standalone dry-run JSON. Correct the local authoritative profile
or its owning engine/environment, then rerun dry-run until aggregate preflight
is green. Run real `sync-profiles` next. If publication fails, take the failed
profile and push-only category from that real JSON report; do not infer it from
dry-run. The real aggregate can publish other profiles, and successful pushes
remain on the remote. Accept the repair only when the real aggregate exits `0`
and the repaired profile is `changed` or `unchanged`. Do not use remote content
to repair an existing local profile.

### Scratch Cleanup

If private scratch cleanup fails, confirm that the affected command has exited
and no bootstrap operation is still running. Inspect the diagnostic and repair
the filesystem problem, such as insufficient permissions or an unavailable path.
Review any directories left by that invocation before removing them: profile
snapshots, Git staging, bootstrap staging and askpass files use the host's
temporary directory; private first-clone stages use
`${HERMES_HOME}/shared/.hermes-repository-*`; initial profile installation uses
`.hermes-profile-home-*` beside `${HERMES_HOME}`. Use the exact identified paths and
preserve anything whose ownership or contents are uncertain. Scratch data can
contain private profile content or credentials, so keep it private until it is
removed.

The command uses ordinary recursive removal for its private scratch directories.
It does not provide mount isolation or protection against another program
replacing files during cleanup.
After repair and cleanup, rerun the failed command. For `sync-profiles`, inspect
the complete JSON report and require exit `0`; completed remote pushes remain
valid and a retry can report them as `unchanged`.

## Apply Failure And Retry

Bootstrap applies staged changes in order and validates the installed layout at
the end. It does not create recovery backups or restore earlier steps if a later
step fails. A failure returns an error and keeps completed local updates and
remote pushes. Repair the reported cause, then rerun `task hermes:sync` to
complete the remaining work and reconcile managed configuration. The gateway
restarts only after the apply succeeds.

Individual configuration and credential files use private
temporary files and atomic replacement. Distribution installation does not
synchronize the entire file tree for power-loss durability. Secret files use
mode `0600`. Existing `.env` files remain untouched. Root updates
are limited to declared owned paths; existing named-profile declarative content
and unmanaged files remain protected. A retry reuses valid managed credentials
and completes the desired configuration without replacing an existing profile
from its remote.

After a crash, `SIGKILL`, or power loss, inspect the reported or interrupted step
and repair its cause before rerunning. There is no whole-apply commit or
automatic restoration guarantee; partially completed changes can remain.

### Data From The Former Transaction Implementation

Current bootstrap creates no transaction directories, backup files, or recovery
journals. It ignores old data under `${HERMES_HOME}/.bootstrap/transactions/`
and never deletes or migrates it. Preserve any old journals or backups until
you have inspected the affected managed paths and decided whether to restore
or keep the current data. Keep it private because it can contain runtime
secrets.

Home Manager enables `gateway.multiplex_profiles` for the native user service.
The root gateway serves managed profiles with profile-scoped credentials,
adapters, routes, and sessions. Use `hermes gateway status` and
`hermes -p <name> gateway status` to verify readiness. The retired Docker
Dashboard/API ports and per-profile s6 services are not part of this flow.

## Engine Lock And Repository Diagnostics

All mutating bootstrap commands share
`${HERMES_HOME}/locks/bootstrap-engine.lock`. Lock acquisition is nonblocking,
and the lock remains held through staging, publication, and cleanup. After
confirming the competing process has exited, rerun the same command.

Git status, index, staged-path, and unpushed-history inspection is bounded to
8 MiB per command and fails closed above that limit. Shared repository
synchronization rejects credential artifacts, runtime state, databases, and
nested Git repositories, while allowing ordinary knowledge filenames such as
`authentication-guide.md` and the repository-root `.env.example`.
Authenticated operations use root-owned Nix-managed Git, a short-lived
`GIT_ASKPASS` file, and the system default `PATH`; credentials are not stored in
remote URLs.

## Shared Repository Layout And Manual Migration

Shared repositories use only `${HERMES_HOME}/shared/<name>`; lifelog uses
`${HERMES_HOME}/shared/lifelog`. Manifest schema version 1 remains current, but
the former `legacy_target` key is unsupported, even when its value is null.
An old manifest is rejected with validation exit code `8` before bootstrap
changes managed paths. Remove that key after migrating the checkout manually.

Bootstrap does not inspect, synchronize, move, or remove
`${HERMES_HOME}/core/lifelog`, including old compatibility links and empty
directories. An old checkout can contain changes or commits unavailable from
origin; migrate it before running bootstrap, which otherwise clones from origin
at the canonical target.

For manual migration, stop the gateway and any bootstrap or lifelog sync
processes. Back up both paths and inspect each real checkout with `git status`,
`git remote get-url origin`, and `git log --all --not --remotes`; verify the
expected origin and retain uncommitted files and local commits. If only the old
path has a real checkout and the canonical path is absent, move the entire
checkout (including `.git`) to `${HERMES_HOME}/shared/lifelog` and verify that
the status, HEAD, origin, and local commits match the backup. If both paths have
data, reconcile their changes and history manually before choosing the canonical
checkout; bootstrap no longer detects or resolves that old-layout collision.
Treat an empty canonical directory or a compatibility symlink separately and
preserve it until its identity and contents are understood. Never overwrite a
checkout or delete repository data as part of this procedure. Remove
`legacy_target` from the manifest, run bootstrap, and restart the gateway after
validation succeeds.

Existing canonical checkouts still undergo origin validation, locked remote
synchronization, conflict detection, and validation before publication. A
published first clone remains available if a later apply step fails; retry uses
that canonical checkout. Completed remote pushes also remain valid.

## Apply Conflicts

- Existing root files are replaced only when declared by
  `root-distribution.yaml`. Existing named profiles follow the local-authority
  rules above and are never repaired by forced remote replacement.
- Existing `.env` files are unmanaged and remain untouched. Bootstrap updates
  native 1Password references without persisting resolved GitHub, Discord, or
  xAI values to runtime environment files.

## Complete Exit Codes

| Code | Meaning                                                               | Operator action                                                                                                   |
| ---- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `0`  | Success                                                               | Continue                                                                                                          |
| `1`  | Host secret-plan or payload production failed                         | Fix `op` or adapter input and rerun                                                                               |
| `2`  | Invalid command arguments, payload, or managed env input              | Correct input and rerun                                                                                           |
| `3`  | Missing, invalid, or unauthorized credential                          | Repair 1Password or GitHub access                                                                                 |
| `4`  | Repository access, identity, lock, profile preflight, or sync failure | Repair the reported repository/profile state                                                                      |
| `5`  | Retired migration status (reserved for compatibility)                 | Current bootstrap does not emit this for old-layout conflicts; follow the manual migration procedure before apply |
| `6`  | Apply, cleanup, or unexpected command failure                         | Inspect safe diagnostics and rerun                                                                                |
| `8`  | Manifest, staged source, or final layout validation failed            | Repair the reported input/layout and rerun                                                                        |

`sync-profiles` uses its JSON route only for handled exits `0`, `3`, and `4`.
Its argument error `2`, manifest validation error `8`, and unexpected error `6`
use stderr without a result document. Failed `apply` likewise uses stderr.
Its default output is the single safe error described above; debug mode may
append only the sanitized public-boundary traceback.

## Future Handoff

The two-hour profile-sync cron handoff and its private Slack channel ID are
future `hermes-home` Task 7 work. They are not deployed by the current
bootstrap or this operations change. Any future root-owned wrapper must invoke
the same aggregate command and must remain local-to-remote for existing named
profiles.

## Source Validation Gate

共有 `Bootstrap CI` は Hermes の構成適用を WSL の `nixos-rebuild switch` と
macOS の `darwin-rebuild switch` で確認します。個別の Hermes Python suite、
NixOS build check、個別 cask artifact build は CI の gate に含めません。
Linux native host の system と standalone Home Manager は構成 build を行い、
Hermes browser の shell runtime contract は個別に確認します。

Python の unittest suite は自動 CI では実行しません。変更の適用確認は対象 platform の
rebuild job を通して行います。

The same source validation requires every root and managed profile distribution
to own `config.yaml`. Bootstrap validates the Chrome MCP guardrails, then
reconciles the non-secret `mcp_servers.xapi` entry in each installed runtime config
with URL `http://127.0.0.1:8766/mcp` and `connect_timeout: 300`. The generated
entry is not written back to source repositories.

Named-profile default branches are exact mirrors. A real sync deletes
repository-local `.github` workflows, pre-commit configuration, validators,
tests, and README files because they are outside the local declarative
allowlist. Therefore named-profile mirrors, including Nancy, are not governed
by a repository-local `fast`/`full` or GitHub Actions validator contract.
Their validation path is:

- runtime aggregate snapshot preflight and `sync-profiles` result handling;
- dotfiles runtime activation through shared `Bootstrap CI` GitHub Actions.

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

Changes are verified by the selected platform's real configuration activation in
`Bootstrap CI`. The workflow does not run the Python unittest suite.

Local Python regression tests focus on this personal dotfiles workflow:

- End-to-end bootstrap and profile publication use real local Git repositories
  to check installation, user-data preservation, safe output, and recovery by rerun.
- Focused unit tests cover secret handling, atomic-write failure recovery,
  existing-target protection, non-force push, deletion limits, and the engine lock.
- Nix configuration values and generated manifests are covered by the Nix checks.

Keep these representative checks small. Add a focused regression test for an
observed bug when the existing operation tests do not detect it; avoid duplicating
their successful paths or exhaustively testing private helper inputs.
