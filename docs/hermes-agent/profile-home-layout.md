# Hermes Agent Home/Profile Layout

The host Hermes directory is mounted at `${HERMES_HOME}`, which is the runtime root
and `HERMES_HOME`. It is never a Git checkout.

```text
host ~/.hermes/                    container ${HERMES_HOME}/
├── config.yaml                    root distribution-owned config
├── SOUL.md                        root distribution-owned profile
├── profile.yaml
├── profiles/
│   ├── rick/                      Hermes distribution target; local-authoritative when present
│   ├── hoffman/
│   ├── risarisa/
│   ├── nancy/
│   ├── kuroda/
│   └── shiraishi/
├── shared/
│   └── lifelog/                   the one writable shared Git checkout
├── memories/                      runtime state
├── sessions/
└── logs/
```

## Ownership

The root profile is displayed as **Alfred**; Hermes reserves its internal ID
`default` and keeps its home at `${HERMES_HOME}`. The former `career-ops`, `dev-lab`,
and `personal-ops` profiles are now `clara`, `ada`, and `sophia` respectively.
Their repositories are `hermes-profile-clara`, `hermes-profile-ada`, and
`hermes-profile-sophia`. Existing sessions stay in the renamed profile homes.
These three profiles have dedicated Discord bots in the Hermes Agents server.
Their bot tokens are stored in the `openclaw` 1Password vault under `Clara`,
`Ada`, and `Sophia`, using the `Discord/bot_token` field. Each existing runtime
home has a native `secrets.onepassword` mapping;
the allowed-user reference is shared from `Master/Discord/allowed_users`.
These runtime mappings do not add the three profiles to the bootstrap manifest.
The root Discord bot was renamed from Master to Alfred without changing its ID.

- Root declarative content remains remote-authoritative from
  `rurusasu/hermes-profile-alfred` at `main`; `root-distribution.yaml` declares the only
  root paths bootstrap may replace.
- The bootstrap manifest currently declares six named distribution targets:
  `rick`, `hoffman`, `risarisa`, `nancy`, `kuroda`, and `shiraishi`, each with a matching
  `rurusasu/hermes-profile-<name>` remote.
- An existing valid named home is local-authoritative. Bootstrap snapshots only
  its locally declared `distribution_owned` content, publishes the exact
  allowlisted remote tree, stages that exact commit, and applies it through the
  official Hermes distribution API.
- A named home is never a Git checkout. Do not run `git init`, clone, or
  checkout in `${HERMES_HOME}/profiles/<name>`; normal and dry-run sync leave local
  bytes and modes unchanged. Empty directories have no Git representation.
- Only a truly absent named target is seeded from its configured remote for
  first install. An existing malformed target fails rather than falling back to
  remote content. This rule is based on target existence and manifest validity,
  not on a hard-coded profile name.
- `shared/lifelog` remains the canonical shared repository. Run
  `hermes-bootstrap sync-repository lifelog` under the shared engine lock. This is
  a normal read-write Git workflow, not named-profile exact mirroring, and every
  profile uses the same path.
- `core/lifelog` is unmanaged; bootstrap neither migrates nor deletes it.
  Reconcile and verify any old checkout using the
  [manual migration procedure](bootstrap.md#shared-repository-layout-and-manual-migration)
  before running bootstrap, preserving local changes and commits. Runtime
  configuration uses `${HERMES_HOME}/shared/lifelog`.
- Bootstrap installs the shared X API MCP endpoint into every staged managed
  distribution as `mcp_servers.xapi.url: http://127.0.0.1:8766/mcp` with
  `connect_timeout: 300`. The endpoint is served by the separate Compose
  `xapi-mcp` container and uses the shared root `.xurl` OAuth cache.
- Bootstrap enables the native LCM context engine and plugin. Memory-provider
  settings and runtime files remain user-managed and are preserved.

Remote named-profile repositories are exact local projections: canonical
`.gitignore`, canonical `distribution.yaml`, and declared owned paths only.
Stale remote workflows, README files, validators, and other allowlist-external
paths are deleted during a real sync.

Do not run a second Hermes gateway process against this runtime root or a
managed profile while the native Hermes gateway can see it. Bootstrap does not
read or write root/profile `.env` files. Existing files remain unmanaged and
must never be committed. Runtime secrets use native 1Password references and
process environment variables.

See [Hermes Bootstrap Operations](bootstrap.md) for commands and recovery, and
[Local-Authoritative Sync Design](profile-local-authoritative-sync-design.md)
for the full sync contract.

## Machine-local dependencies

Hermes 0.22 reserves root-level `tools/`, `installs/`, and `cache/` in the root
home and every named profile for PM-managed tools and dependency generations.
They must not appear in `distribution_owned`, profile exports, or shared profile
repositories. Bootstrap rejects such ownership before publishing snapshots or
applying distributions, while preserving the original files.

Place authored executable files in `scripts/` or `skills/<name>/scripts/`.
Nested names such as `skills/<name>/tools/` remain ordinary portable content;
the PM reservation applies to the first path component.

For cron definitions, only `cron/jobs.json` is portable. Named-profile imports
merge those definitions by job ID and start new jobs paused for review. The
custom root distribution retains its explicit remote-authoritative ownership.
Bootstrap
rejects other root-level cron files before publication or installation, even
when the manifest owns the whole `cron/` directory, because Hermes would omit
them. Nested application assets such as `skills/<name>/cron/task.yaml` are
unaffected. Convert legacy cron assets to supported job definitions or keep
ordinary scripts under `scripts/` and update their references.

For an older home, first back up authored files outside the Hermes home. Move
only files explicitly owned by its distribution from `tools/` or `installs/`
to `scripts/`, then update `distribution_owned` and references to those paths.
Do not move entire PM directories: their facts and dependencies belong to the
current machine, and PM garbage collection may remove unknown store entries.
Do not rely on profile export/import to preserve legacy authored files in these
directories; current Hermes deliberately excludes them. Keep the external
backup until the updated profile and its commands have been verified.

On a fresh machine with no `~/.hermes`, no data relocation is needed. The first
bootstrap uses this layout and validates the configured profile distributions.
