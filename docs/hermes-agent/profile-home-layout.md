# Hermes Agent Home/Profile Layout

Hermes profile homes should keep the filesystem layout that Hermes expects, while Git tracks only the declarative distribution files.

## Runtime Mounts

- The default gateway mounts `~/.hermes` as `/opt/data`.
- A dedicated profile gateway mounts `~/.hermes/profiles/<profile>` as `/opt/data`.
- A dedicated profile gateway mounts the root shared docs directory `~/.hermes/docs` onto `/opt/data/docs` read-only.
- From the default gateway, profile homes are visible under `/opt/data/profiles/<profile>`.

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

## Dedicated Gateway Runtime Secrets

A profile that runs its own gateway still needs runtime credentials inside that profile home. Put dashboard auth, Slack tokens, and other env-based secrets in the profile `.env`; put model-provider auth in the profile `auth.json` or provider-specific env vars. Provision these locally or from a secrets manager, and keep them out of Git.

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
