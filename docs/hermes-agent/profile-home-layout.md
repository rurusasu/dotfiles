# Hermes Agent Home/Profile Git Layout

Hermes home directories are Git-managed profile distributions. Git should track declarative agent configuration, not live runtime state.

## Directory Model

- `~/.hermes` maps to `/opt/data` in the Hermes container and is the default profile home repository.
- `~/.hermes/profiles/researcher` maps to `/opt/data/profiles/researcher` and should be managed as a separate profile repository.
- The root home repository ignores `profiles/` so nested profile homes do not appear as giant untracked trees.

## Track

- `config.yaml`
- `SOUL.md`
- `profile.yaml`
- Curated skills and profile-specific docs
- Declarative cron job definitions
- Shared operational docs
- Project guidance in repository `AGENTS.md`

## Ignore

- `.env`, `.env.*`, `auth.json`, tokens, and secrets
- `memories/`, `sessions/`, `logs/`, `state.db*`, gateway state, locks, pids, caches, generated usage files, and workspaces
- Profile runtime state in every profile home

## Shared Agent Reading

The Hermes setup handler deploys a runtime copy to:

```text
/opt/data/docs/profile-home-layout.md
```

Profile-specific homes also receive:

```text
/opt/data/profiles/<profile>/docs/profile-home-layout.md
```

Each managed profile `SOUL.md` gets a small managed pointer to these docs so agents can find the policy before changing home/profile layout.

## Sharing Knowledge

Do not share profile `memories/` through Git. Put durable shared guidance in docs or `AGENTS.md`, and use Slack, Kanban, GitHub issues, or Linear for cross-agent work state. If a shared memory backend is introduced later, namespace it by user, app, and profile.
