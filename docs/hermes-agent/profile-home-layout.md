# Hermes Agent Home/Profile Layout

The host Hermes directory is mounted at `/opt/data`, which is the runtime root
and `HERMES_HOME`. It is never a Git checkout.

```text
host ~/.hermes/                    container /opt/data/
├── .env                           root runtime secrets
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
├── hindsight/
│   ├── config.json                 root/default managed Hindsight provider config
│   ├── pg0/                        Hindsight embedded PostgreSQL data
│   └── cache/                      local reranker cache
├── memories/                      runtime state
├── sessions/
└── logs/
```

## Ownership

- Root declarative content remains remote-authoritative from
  `rurusasu/hermes-home` at `main`; `root-distribution.yaml` declares the only
  root paths bootstrap may replace.
- The bootstrap manifest currently declares six named distribution targets:
  `rick`, `hoffman`, `risarisa`, `nancy`, `kuroda`, and `shiraishi`, each with a matching
  `rurusasu/hermes-profile-<name>` remote.
- An existing valid named home is local-authoritative. Bootstrap snapshots only
  its locally declared `distribution_owned` content, publishes the exact
  allowlisted remote tree, stages that exact commit, and applies it through the
  official Hermes distribution API.
- A named home is never a Git checkout. Do not run `git init`, clone, or
  checkout in `/opt/data/profiles/<name>`; normal and dry-run sync leave local
  bytes and modes unchanged. Empty directories have no Git representation.
- Only a truly absent named target is seeded from its configured remote for
  first install. An existing malformed target fails rather than falling back to
  remote content. This rule is based on target existence and manifest validity,
  not on a hard-coded profile name.
- `shared/lifelog` remains the canonical shared repository. The default profile
  is its `sync_owner` and runs
  `hermes-bootstrap sync-repository lifelog` under the repository lock. This is
  a normal read-write Git workflow, not named-profile exact mirroring, and every
  profile uses the same path.
- `core/lifelog` is accepted only as a migration source and is absent after
  bootstrap. Runtime configuration uses `/opt/data/shared/lifelog`.
- Bootstrap installs the shared X API MCP endpoint into every staged managed
  distribution as `mcp_servers.xapi.url: http://xapi-mcp:8080/mcp` with
  `connect_timeout: 300`. The endpoint is served by the separate Compose
  `xapi-mcp` container and uses the shared root `.xurl` OAuth cache.
- Bootstrap transactionally manages `hindsight/config.json` in the root and in
  every named profile. The directory is mode `0700` and `config.json` is mode
  `0600`; it configures the profile-specific Hindsight bank but is not a profile
  distribution-owned Git path.
- Shared Hindsight database data is `${HINDSIGHT_DATA_DIR}/pg0` and its
  reranker cache is `${HINDSIGHT_DATA_DIR}/cache` (default:
  `~/.local/share/hindsight`). These are host-level runtime data, not profile Git
  repository content. Named profile configuration files likewise do not place
  retained memory data in their profile repositories.

Remote named-profile repositories are exact local projections: canonical
`.gitignore`, canonical `distribution.yaml`, and declared owned paths only.
Stale remote workflows, README files, validators, and other allowlist-external
paths are deleted during a real sync.

Do not run a second Hermes gateway container against this runtime root or a
managed profile while the main Hermes container can see it. Root and named
profile `.env` files are runtime-only, mode `0600`, and must never be
committed.

See [Hermes Bootstrap Operations](bootstrap.md) for commands and recovery, and
[Local-Authoritative Sync Design](profile-local-authoritative-sync-design.md)
for the full sync contract. See [Hermes Hindsight ローカルメモリ運用](hindsight-memory.md)
for memory bank mapping, backup/restore, and privacy limits.
