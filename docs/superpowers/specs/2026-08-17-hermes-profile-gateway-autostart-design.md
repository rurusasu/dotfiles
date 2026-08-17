# Hermes Profile Gateway Autostart Design

## Goal

Make the first `nrs` or supported dotfiles installation start every configured
Hermes profile Gateway, not only `default`. Installation succeeds only after
all registered Gateways are running and their configured Discord connections
are connected.

## Current behavior

The shared bootstrap recreates the Hermes Compose stack with `gateway run` as
the container command. Hermes redirects that command to the supervised
`gateway-default` service. Named profile services are registered by s6, but a
profile without a persisted `gateway_state.json` remains down until an
operator runs `hermes -p <profile> gateway start`.

Consequently, a fresh Hermes data directory starts `default` while leaving all
named profiles stopped. Later container recreations preserve only Gateways
that have already recorded `desired_state=running`.

## Chosen approach

Add one in-container Gateway convergence command to the dotfiles Hermes image.
It discovers the runtime's registered `gateway-*` s6 services, starts every
profile through Hermes' service-manager lifecycle, and waits for each profile
to report:

- an active supervised process;
- `desired_state=running`; and
- `platforms.discord.state=connected` when Discord is configured.

The Unix and Windows bootstrap adapters invoke this same command after Compose
recreates the stack. This keeps profile discovery and readiness semantics in a
single cross-platform implementation and automatically includes profiles added
in the future.

Fixed profile lists in Shell and PowerShell are rejected because they duplicate
configuration and can omit new profiles. Separate Compose services per profile
are rejected because that is a larger resource and deployment redesign than
this startup contract requires.

## Components and data flow

1. Bootstrap applies profile configuration and recreates the Compose stack.
2. The existing default API readiness check confirms the container is ready for
   lifecycle commands.
3. The common in-container command enumerates registered s6 Gateway services.
4. It starts each service idempotently through the Hermes service manager,
   which records `desired_state=running` in the correct profile home.
5. It polls supervised process state and profile Gateway state until every
   profile is ready or the bounded timeout expires.
6. The host bootstrap continues only after convergence succeeds.

## Error handling

The command validates every discovered profile name before using it. An empty
Gateway set, lifecycle error, process exit, Discord error state, or readiness
timeout returns nonzero and identifies the affected profile. The host bootstrap
propagates that failure, so `nrs` and every supported installer fail closed.

Gateways that started successfully are not stopped when another profile fails.
Their persisted running state is useful for diagnosis and allows the next
idempotent run to converge without disrupting healthy profiles. No credentials
or token values are printed.

## Platform scope

The convergence implementation lives in the shared Docker image. Unix Shell
and Windows PowerShell host adapters call the same executable after startup.
The macOS `nrs`, Linux installers, NixOS installers, WSL setup, and Windows
bootstrap therefore receive the same behavior without duplicating profile
logic.

## Tests

Automated coverage will prove:

- a fresh profile without Gateway state is started;
- all registered profiles are discovered, including future names;
- repeated convergence is idempotent;
- lifecycle failures and readiness timeouts fail the command;
- disconnected or errored Discord state fails readiness;
- Unix and Windows adapters invoke convergence after Compose startup and
  propagate a nonzero result;
- the existing focused bootstrap, installer, Shell, PowerShell, formatting,
  and lint checks remain green.

Live verification will confirm all seven current profiles report supervised
`up`, persisted `desired_state=running`, and Discord `connected`. It will not
send Discord messages unless separately authorized.
