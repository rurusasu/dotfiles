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
│   ├── rick/                      official Hermes distribution target
│   ├── hoffman/                   official Hermes distribution target
│   └── risarisa/                  official Hermes distribution target
├── shared/
│   └── lifelog/                   the one writable shared Git checkout
├── memories/                      runtime state
├── sessions/
└── logs/
```

## Ownership

- The root declarative source is `rurusasu/hermes-home` at `main`; its
  `root-distribution.yaml` declares the only root paths bootstrap may replace.
- `profiles/rick`, `profiles/hoffman`, and `profiles/risarisa` are installed
  with the official Hermes distribution API from
  `rurusasu/hermes-profile-rick`, `rurusasu/hermes-profile-hoffman`, and
  `rurusasu/hermes-profile-risarisa`. Each source has `distribution.yaml` and
  targets the matching directory under `/opt/data/profiles/`.
- Named profiles retain their runtime `.env`, `auth.json`, memories, sessions,
  logs, workspaces, and gateway state, but are not Git repositories.
- `shared/lifelog` is the canonical shared repository. The default profile owns
  its locked read-write Git synchronization; every profile uses the same path.
- `core/lifelog` is accepted only as an old migration source and is absent
  after bootstrap. All runtime configuration uses `/opt/data/shared/lifelog`.
- Root and named-profile source repositories own declarative config, policy,
  cron, scripts, and MCP declarations. The bootstrap stages those sources and
  applies them transactionally without turning runtime homes into Git working
  trees.

Do not run a second Hermes gateway container against this runtime root or a
managed profile while the main Hermes container can see it. Do not initialize a
profile repository, copy profile Git metadata into `/opt/data`, or share
runtime memories and sessions through Git. Root and profile `.env` files are
runtime-only, mode `0600`, and must never be committed.

See [Hermes Bootstrap Operations](bootstrap.md) for installation and recovery
behavior.
