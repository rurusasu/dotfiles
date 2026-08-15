# Hermes Hindsight Qwen Memory Design

## Goal

Give every managed Hermes profile fully local, persistent long-term memory by
connecting Hermes's bundled Hindsight memory provider to a self-hosted
Hindsight service and native Ollama. Keep profile memories isolated, manage all
non-secret configuration from this dotfiles repository, use the Apple GPU on
macOS, and preserve normal Hermes conversations when the memory service is
temporarily unavailable.

The managed profiles are `default`, `rick`, `hoffman`, `risarisa`, `nancy`,
`kuroda`, and `shiraishi`. No profile is treated as representative during
verification.

## Scope

This change covers:

- native Ollama installation through the cross-platform package catalog;
- the Hindsight runtime and persistent data under the Hermes Compose stack;
- Qwen LLM and embedding model provisioning;
- profile-local Hermes Hindsight configuration for every manifest profile;
- runtime health checks, profile-isolation checks, and operator documentation.

Hindsight is already a bundled Hermes memory provider. The design does not
install another user plugin under `~/.hermes/plugins`, fork Hermes core, or add a
custom memory provider. Cloud LLM fallback, cloud memory storage, shared
cross-profile banks, and migration of old built-in `MEMORY.md` data are out of
scope. Hermes's built-in `MEMORY.md` and `USER.md` remain enabled alongside
Hindsight. The Hermes image installs a tested `hindsight-client` version during
its build so gateway startup never depends on a runtime package download.

## Chosen architecture

Hermes and Hindsight run in the existing `docker/hermes-agent/compose.yml`
stack. Hindsight uses the PostgreSQL runtime bundled in its official container
instead of adding a separately managed PostgreSQL service. Its database and
model cache are persisted below `${HERMES_DATA_DIR}`. The Hindsight image is
pinned to a tested release rather than a floating `latest` tag.

Ollama runs natively on the host. On macOS this lets the standard GGUF runner
use Apple Metal without placing Ollama in Docker. Hindsight reaches Ollama at
`host.docker.internal:11434`; Compose supplies a `host-gateway` mapping so the
same service definition also works on Linux. Windows and macOS use Docker's
native host alias. No runtime request is sent to a cloud model or memory API.

The runtime flow is:

```text
Hermes profile
  -> bundled Hindsight memory provider
     -> Hindsight API in Docker
        -> embedded PostgreSQL and local CPU reranker
        -> native host Ollama
           -> qwen3.6:35b
           -> qwen3-embedding:0.6b
```

Hermes and Hindsight do not share a restart dependency. Installation and
acceptance checks require a healthy memory stack, but a later Hindsight outage
must not stop or restart the Hermes gateway.

## Model configuration

The selected model pipeline is:

| Role                                           | Model                       | Runtime                                      |
| ---------------------------------------------- | --------------------------- | -------------------------------------------- |
| Fact extraction, consolidation, and reflection | `qwen3.6:35b` standard GGUF | Native Ollama with Metal where available     |
| Embedding                                      | `qwen3-embedding:0.6b`      | Ollama OpenAI-compatible embeddings endpoint |
| Reranking                                      | `BAAI/bge-reranker-v2-m3`   | Local CPU inside Hindsight                   |

The Qwen LLM uses a 32,768-token context, one concurrent Hindsight LLM request,
reasoning disabled, and strict JSON Schema for retain, reflect, and
consolidation operations. The standard GGUF Ollama model is required; MLX tags
are excluded because the Ollama MLX runner has unresolved JSON Schema
enforcement defects. The multilingual BGE reranker remains separate because
the Qwen reranker path through Ollama/llama.cpp has unresolved correctness
issues.

`nix/packages/sets.nix` remains the package installation source of truth.
Ollama is added there with platform providers instead of editing generated
Windows package data by hand. Model names live in one declarative Hermes memory
configuration and platform adapters only perform installation, daemon checks,
and idempotent model pulls.

## Hermes profile configuration

Bootstrap manages the following section in the root and every named profile's
`config.yaml`, preserving unrelated user-owned keys:

```yaml
memory:
  provider: hindsight
```

Bootstrap also atomically writes profile-scoped
`$HERMES_HOME/hindsight/config.json` files equivalent to:

```json
{
  "mode": "local_external",
  "api_url": "http://hindsight:8888",
  "bank_id": "hermes",
  "bank_id_template": "hermes-{profile}",
  "bank_retain_mission": "Retain durable preferences, decisions, corrections, entities, relationships, and temporal facts. Never extract credentials, tokens, private keys, authentication material, or transient logs as memories.",
  "memory_mode": "hybrid",
  "auto_recall": true,
  "recall_sync": false,
  "recall_types": "observation",
  "recall_budget": "mid",
  "auto_retain": true,
  "retain_async": true,
  "retain_every_n_turns": 1,
  "retain_source": "hermes"
}
```

The bootstrap manifest is the source of the profile inventory. Configuration
generation iterates that inventory and never hard-codes a shorter profile list.
An invalid existing YAML or JSON document fails the transaction without
partially updating other profiles. A second successful apply is idempotent.

## Memory isolation and data flow

`bank_id_template` resolves one deterministic bank per active profile:

```text
hermes-default
hermes-rick
hermes-hoffman
hermes-risarisa
hermes-nancy
hermes-kuroda
hermes-shiraishi
```

No normal recall or retain operation crosses those bank boundaries, and no
shared bank is created in this scope.

Before a turn, Hermes performs Hindsight prefetch in the background. With
`recall_sync: false`, relevant observations are injected on the following turn
without adding synchronous Hindsight latency to the current response. The
provider exposes explicit recall, retain, and reflect tools through
`memory_mode: hybrid` when immediate or deliberate memory operations are
needed. Recall returns Hindsight's consolidated `observation` records by
default instead of duplicating their underlying raw facts.

After every completed turn, the bundled provider asynchronously retains the
user content and final assistant content. It does not retain arbitrary tool
output through this automatic turn path. Hindsight extracts facts, temporal
information, entities, relationships, corrections, user preferences, and
decisions, then builds observations for later recall.

## Persistence and network exposure

The Hindsight embedded database and model cache use explicit persistent mounts
below `${HERMES_DATA_DIR}/hindsight`. Recreating or upgrading the container must
not discard memory or redownload the reranker. Database migration behavior is
verified before accepting a Hindsight version update.

Hermes reaches the API over a dedicated Compose network. The Hindsight API and
UI may be mapped to host ports for diagnostics, but only on `127.0.0.1`.
PostgreSQL is never published directly. The host Ollama listener remains a
host-local service; the Docker host alias is the only intended container path
to it.

## Security and privacy boundary

All inference, embeddings, reranking, and memory storage stay local. The
configuration contains no required API key. Repository files must not contain
credentials or generated memory data.

The standard Hermes Hindsight provider sends the user message and final
assistant response to the local Hindsight API. It has no guaranteed
pre-retain secret redaction hook. A `bank_retain_mission` instructs Hindsight
not to extract credentials, tokens, private keys, or authentication material as
facts, but the original local retained document can still contain text pasted
directly into chat. Operators therefore must not paste secrets into Hermes
conversations. Adding a custom redaction provider or patching the bundled
provider is explicitly out of scope.

## Failure handling

Setup fails clearly when Ollama is absent, its daemon is unreachable, either
Qwen model is missing, Hindsight cannot connect to its database, the configured
Hindsight version is incompatible, or a strict-schema probe fails. These
failures are never reported as successful installation.

At runtime, recall failure produces no injected memory and does not fail the
Hermes turn. Retain failure is logged as a failed save rather than a successful
memory write. Hermes continues using its built-in memory and session data.
After Hindsight recovers, new recall and retain requests resume without a
Hermes restart. There is no cloud fallback.

## Test strategy

### Repository and CI tests

Add tests that prove:

- all seven manifest profiles receive the provider and profile-local config;
- the bank template stays `hermes-{profile}`;
- the Hermes image contains the required tested `hindsight-client` version;
- unrelated YAML and JSON settings survive reconciliation;
- repeated apply is idempotent;
- malformed input triggers rollback instead of partial writes;
- the Compose image is pinned, data/cache mounts persist, health checks exist,
  PostgreSQL is private, and host ports bind only to loopback;
- Linux host-gateway behavior and macOS/Windows host alias behavior are
  represented in the Compose contract;
- Ollama's package catalog entry and generated platform data agree;
- model provisioning adapters request the exact selected models and propagate
  failures.

Run the existing bootstrap unit and integration suites, Compose validation,
package-catalog tests, shell tests, PowerShell tests, formatting, linting, and
repository pre-commit checks affected by the final diff. Tests are not skipped
because a model or platform dependency is inconvenient; unavailable live
hardware is reported separately from deterministic CI results.

### macOS live acceptance

The target Mac must pass all of the following before the pull request is
merged:

1. Ollama loads `qwen3.6:35b` through its Metal-capable standard runner.
2. `qwen3-embedding:0.6b` returns embeddings through the configured endpoint.
3. Hindsight reports healthy with a connected embedded database.
4. Twenty repeated strict-JSON extraction probes all succeed.
5. Japanese and English cases retain and recall dates, corrections,
   preferences, entities, and decisions correctly.
6. Hindsight restart preserves retained data and avoids reranker redownload.
7. Stopping Hindsight does not stop a Hermes response, and recovery restores
   recall and retain.
8. Retain and recall complete within the configured 300-second timeout without
   process termination or critical macOS memory pressure.

Record retain and recall p50/p95 latency and observed memory pressure as
acceptance evidence. They are diagnostic measurements, while the timeout and
system-stability requirements are pass/fail gates.

### All-profile isolation acceptance

Exercise `default`, `rick`, `hoffman`, `risarisa`, `nancy`, `kuroda`, and
`shiraishi` individually. Each profile stores and recalls its own unique
sentinel and fails to recall all six other sentinels. The test records the
resolved bank ID for every operation. It uses uniquely named temporary test
banks derived through the real profile resolver, not production banks, and
deletes only those known test banks after successful evidence collection.

## Documentation and operation

Create `docs/hermes-agent/hindsight-memory.md` with installation, model pull,
start, status, log, backup, restore, upgrade, profile-isolation verification,
and degraded-mode procedures. Common task entry points should provision and
verify the memory stack without requiring operators to reproduce raw Compose or
Ollama commands. The documentation must distinguish local macOS acceptance,
CI validation, and any unverified platform runtime state.

## Upstream references

- Hermes memory providers:
  <https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory-providers.md>
- Hermes Hindsight provider:
  <https://github.com/NousResearch/hermes-agent/blob/main/plugins/memory/hindsight/README.md>
- Hindsight:
  <https://github.com/vectorize-io/hindsight>
- Qwen3.6 35B A3B:
  <https://huggingface.co/Qwen/Qwen3.6-35B-A3B>
- Qwen3 Embedding 0.6B:
  <https://huggingface.co/Qwen/Qwen3-Embedding-0.6B>
- BGE Reranker v2 M3:
  <https://huggingface.co/BAAI/bge-reranker-v2-m3>
