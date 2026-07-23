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
│   └── nancy/
├── shared/
│   └── lifelog/                   the one writable shared Git checkout
├── memories/                      runtime state
├── sessions/
└── logs/
```

## Ownership

- Root declarative content remains remote-authoritative from
  `rurusasu/hermes-home` at `main`; `root-distribution.yaml` declares the only
  root paths bootstrap may replace.
- The bootstrap manifest currently declares four named distribution targets:
  `rick`, `hoffman`, `risarisa`, and `nancy`, each with a matching
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
  owns its locked read-write Git synchronization and every profile uses that
  same path.
- `core/lifelog` is accepted only as a migration source and is absent after
  bootstrap. Runtime configuration uses `/opt/data/shared/lifelog`.

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
for the full sync contract.
