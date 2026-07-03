# Hermes Agent Home/Profile Layout

Hermes profile homes should keep the filesystem layout that Hermes expects, while Git tracks only the declarative distribution files.

## Runtime Mounts

- The Hermes Docker service mounts `~/.hermes` as `/opt/data`.
- Inside the official Docker image, s6 supervises profile gateways as `/run/service/gateway-<profile>` within that same container.
- Profile homes stay visible under `/opt/data/profiles/<profile>` and keep their own `.env`, config, cron, memory, sessions, and gateway state.
- Do not run another Hermes gateway container against `~/.hermes` or any `~/.hermes/profiles/<profile>` directory while the root container can see that profile.
- `HERMES_DATA_DIR` remains the Hermes home. Do not point it at lifelog; lifelog is restored under `~/.hermes/core/lifelog`.

## Standard Profile Filesystem

`hermes profile create <name>` scaffolds a usable profile home. Depending on flags and runtime activity, a profile home may contain files and directories such as:

```text
~/.hermes/profiles/<profile>/
  .env
  .gitignore
  .no-bundled-skills
  config.yaml
  SOUL.md
  profile.yaml
  slack-manifest.json
  assets/
  docs/
  cron/
  home/
  logs/
  memories/
  plans/
  sessions/
  skills/
  skins/
  workspace/
  state.db*
```

Do not delete or flatten this physical layout just to make Git status smaller. Hermes and its gateway may recreate runtime directories as needed.

## Git-Tracked Distribution

Track durable, declarative profile content:

- `config.yaml`
- `SOUL.md`
- `profile.yaml`
- `.gitignore`
- `.no-bundled-skills` when the profile intentionally has no bundled skills
- `slack-manifest.json` when the profile has a Slack app
- `assets/` for durable profile images and icons
- `docs/` for profile-specific docs only; do not copy the shared root layout doc into each profile
- curated profile-specific `skills/`, if intentionally maintained
- declarative `cron/` definitions only, not cron output, locks, or tick files

## Profile Gateway Runtime Secrets

A profile gateway still needs runtime credentials inside that profile home, even when s6 runs it inside the root Docker container. Put dashboard auth, Slack tokens, and other env-based secrets in the profile `.env`; put model-provider auth in the profile `auth.json` or provider-specific env vars. Provision these locally or from a secrets manager, and keep them out of Git.

## Ignored Runtime State

Ignore secrets and live state:

- `.env`, `.env.*`, `auth.json`, tokens, and secrets
- `memories/`, `sessions/`, `logs/`, `state.db*`, gateway state, channel directories, locks, pids, caches, generated usage files, local workspaces, and transient cron output
- default profile state copied by `--clone-all` unless it has been intentionally curated into the profile distribution

## Profile Creation Notes

- `hermes profile create <name>` creates a standard scaffold.
- `hermes profile create --clone <name>` copies `config.yaml`, `.env`, `SOUL.md`, and `skills` from the source profile.
- `hermes profile create --clone-all <name>` copies broader state and is not recommended for clean Git-managed distributions.
- If a profile does not need bundled skills, use or keep `.no-bundled-skills` instead of tracking an empty `skills/` tree.

## Sharing Knowledge

Do not share profile `memories/` through Git. Put durable shared guidance in `docs/` or repository `AGENTS.md` files, and use Slack, Hermes Kanban, GitHub issues, or Linear for cross-agent work state. If a shared memory backend is introduced later, namespace it by user, app, and profile.

## Lifelog Core

`install.cmd` restores the shared lifelog core at:

```text
~/.hermes/core/lifelog
```

Hermes gateways see it at:

```text
/opt/data/core/lifelog
```

Every managed profile should treat `/opt/data/core/lifelog/AGENTS.md` and relevant lifelog notes as the shared source of truth before making user-context decisions. The Hermes home repository ignores `core/`; lifelog is its own Git repository and is synced by the `lifelog_sync.sh` cron job.
