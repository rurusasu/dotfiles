# Issue #511 Optional Profiles and Shared Hindsight Design

## Goal

Keep the default dotfiles installation small, remove Claude and TablePlus, make
Ollama, Docker, and Hermes explicit feature profiles, and let host and Tart Codex
share one independently managed Hindsight service.

## Installer profiles

The Windows entry point remains `install.cmd`. It forwards PowerShell switches to
`install.ps1`, which expands dependencies once and stores the resulting booleans
in `SetupContext.Options`.

| Input         | Effective features                                                       |
| ------------- | ------------------------------------------------------------------------ |
| no switch     | core only                                                                |
| `-WithOllama` | Ollama                                                                   |
| `-WithDocker` | Docker, Ollama, Hindsight                                                |
| `-WithHermes` | Hermes, Docker, Ollama, Hindsight, Chrome, Discord, Chromium/browser-mcp |

Package catalog entries gain a feature marker consumed by the Windows winget and
pnpm handlers. Optional packages are skipped unless the effective feature is
enabled. Claude and TablePlus are deleted from the catalog rather than merely
hidden by a profile.

## Claude removal

Remove Claude CLI and desktop packages, the Windows handler, ACP package,
marketplace/plugin deployment, Claude desktop configuration, editor integrations,
and Claude-only automation. Reusable agent skills move from `~/.claude/skills` to
the neutral `~/.agents/skills` chezmoi source. Codex permission-policy names and
comments become provider-neutral.

## Independent Hindsight

Hindsight has its own Compose project under `docker/hindsight`, persistent data
under `~/.local/share/hindsight`, and lifecycle tasks under `hindsight:*`. It uses
host Ollama for generation and embeddings but is not started, stopped, or restarted
by Hermes.

Hermes and Hindsight join one external Docker network. Hermes retains its own bank
configuration and only checks that the Hindsight API is reachable before starting.
The Hindsight acceptance test owns Hindsight lifecycle; Hermes acceptance verifies
only the Hermes-to-Hindsight integration.

Codex uses managed hooks for `SessionStart`, `UserPromptSubmit`, and `Stop`. Hooks
recall and retain against a configured bank and attach runtime metadata. Host and
Tart use the same bank by default. Ollama is selected directly through Codex's
model-provider configuration when desired; no Ollama command wrapper is added.

## Tart startup

`tart:run` prepares the VM, starts it with an SSH reverse forward from guest
`127.0.0.1:8888` to host `127.0.0.1:8888`, then runs an idempotent guest bootstrap.
The guest compares the remote Git commit with a stored applied commit. When they
match it skips cloning/pulling and applying. When they differ it updates the
checkout, installs the minimal profile (Neovim, WezTerm, chezmoi, Codex plus base
runtime tools), applies chezmoi, and records the commit only after success.

The synchronization accepts an explicit repository URL/ref for tests and private
forks. A failed fetch or apply leaves the previous applied hash intact so the next
startup retries.

## Safety and compatibility

- Hindsight remains bound to host loopback; Tart access uses SSH forwarding.
- Tests inject exact executable paths and must never fall through to host Ollama.
- Existing user data volumes are not deleted during migration.
- The original checkout and unrelated dirty files are outside this worktree.
- Direct `ollama run` sessions are not presented as persistent-memory clients.
