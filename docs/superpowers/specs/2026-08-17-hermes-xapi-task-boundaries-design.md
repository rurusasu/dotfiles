# Hermes X API Task Boundaries Design

## Goal

Make the X API MCP first-time authentication easy to remember while keeping
`nrs` non-interactive and avoiding duplicate lifecycle logic.

## Current behavior

- `hermes:xapi:auth` performs the headless OAuth flow only.
- `hermes:xapi:sync-token` copies the local xurl refresh token into the shared
  1Password item.
- `hermes:xapi:restart` reads the 1Password credentials, materializes the local
  xurl cache, and recreates `xapi-mcp`.
- `nrs` calls `hermes:bootstrap`; the bootstrap adapter already performs the
  1Password-backed xapi setup as part of starting the full Hermes stack.

## Decision

Keep `hermes:xapi:auth` as a public, atomic task and add one composite task:

```text
hermes:xapi:setup
  -> hermes:xapi:auth
  -> hermes:xapi:sync-token
  -> hermes:xapi:restart
```

`auth` is not removed because it remains the reusable OAuth operation for
initial setup and explicit re-authentication after token rotation. It does not
write to 1Password or restart services by itself.

Do not add `hermes:xapi:ensure` in this change. `hermes:bootstrap`, which is
already called by `nrs`, is the existing non-interactive ensure/recovery path.
Adding another xapi ensure task would duplicate that behavior and create two
competing startup paths.

## User-facing flow

For a new PC or explicit re-authentication:

```bash
task hermes:xapi:setup
```

The OAuth callback may show `localhost:8080` as unreachable. The task's
existing headless xurl flow requires the user to paste the complete callback
URL, or its code when requested, into the waiting terminal. After successful
OAuth, the task synchronizes the refresh token to 1Password and restarts the
MCP container.

For normal updates:

```bash
nrs
```

No interactive OAuth task is added to this path. If the shared refresh token is
missing, the existing bootstrap error remains the signal to run the explicit
setup task.

## Implementation boundaries

- Taskfile owns the readable sequence and platform dispatch.
- Existing Bash and PowerShell adapters remain the implementation of each
  atomic operation.
- No secrets are passed as Taskfile arguments or printed in task output.
- The composite task must stop on the first failed step and must not restart
  xapi after an unsuccessful OAuth or token synchronization.
- Existing public task names remain unchanged.

## Verification

Add contract coverage that proves:

1. `hermes:xapi:setup` exists and is interactive.
2. Its dry-run order is `auth`, `sync-token`, then `restart`.
3. `nrs` still routes through `hermes:bootstrap` and does not invoke the
   interactive xapi auth task.
4. Existing adapter and token synchronization tests continue to pass.

Documentation will show `hermes:xapi:setup` as the remembered first-time
command and retain `hermes:xapi:auth` as the low-level recovery command.
