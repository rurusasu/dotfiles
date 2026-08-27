# Local AI Services MLflow Gateway Design

## Status

Approved in conversation on 2026-08-27. The shared Docker network is
`local-ai-services`.

## Goal

Provide a local MLflow AI Gateway that records Ollama-backed model calls from
the current Hindsight service and establishes a mandatory onboarding contract
for future local-AI services.

## Architecture

```text
Host Ollama :11434
        ^ host.docker.internal
        |
MLflow Gateway :5000  <---- local-ai-services ----> Hindsight / future services
        |
        +-- SQLite:  ~/.local/share/mlflow/mlflow.db
        +-- Artifacts: ~/.local/share/mlflow/artifacts/
```

MLflow runs as an independent Compose project in `docker/mlflow/compose.yml`.
The host publishes it only on `127.0.0.1:5000`; container clients use
`http://mlflow:5000` over the external `local-ai-services` bridge network.
Only MLflow contacts host Ollama directly. The MLflow container has the
`host.docker.internal:host-gateway` mapping.

The MLflow image uses a released, pinned version and digest. `latest` is not
used. The server uses the explicit backend URI `sqlite:////mlflow/mlflow.db`.
The host data root is `${MLFLOW_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/mlflow}`
and bind-mounts the database and `artifacts/` directory. MLflow stores Gateway
endpoint definitions, experiments, runs, and trace metadata in SQLite.

SQLite is appropriate for one local user and low-to-moderate concurrency. The
client contract does not depend on the database type, so PostgreSQL can later
replace it. Migrate when multiple users share the server, sustained concurrent
writes produce lock or latency failures, or the service becomes an always-on
shared deployment.

Trace payloads may contain prompts, responses, token metadata, and latency.
The data root is private local runtime data, never Git content, and the docs
must include backup and retention guidance.

## Naming and endpoints

The network is `local-ai-services`, independent of MLflow and Ollama product
names. Logical Gateway endpoints are capability-oriented and stable:

| Endpoint                   | Provider | Initial model          | Capability       |
| -------------------------- | -------- | ---------------------- | ---------------- |
| `ollama-chat-default`      | `ollama` | `qwen3.6:35b`          | chat/completions |
| `ollama-embedding-default` | `ollama` | `qwen3-embedding:0.6b` | embeddings       |

Clients use endpoint names rather than provider model strings. Model changes
therefore do not require changing every client.

## Gateway configuration

`docker/mlflow/endpoints.yml` is the repository source of truth for local
Ollama endpoint definitions. It contains endpoint names, provider, Ollama base
URL, model names, capabilities, and tracing settings; it contains no secrets
or prompt data.

`task mlflow:configure` applies the manifest idempotently using MLflow's
documented Gateway API. It creates or updates model definitions and endpoints,
enables `usage_tracking`, and associates endpoint invocations with MLflow
experiments as required by the pinned server version. Repeated runs must not
duplicate resources.

## Service onboarding contract

Every new Ollama-backed service declares a service identifier, capability,
logical endpoint, connection mode, and a live verification command proving
that a request created a trace.

OpenAI-compatible Gateway clients use:

```text
MLFLOW_GATEWAY_URL=http://mlflow:5000/gateway/mlflow/v1
MLFLOW_MODEL=ollama-chat-default
```

Host-native clients use the same path through `http://127.0.0.1:5000`.
Docker services using the Gateway join `local-ai-services` and must not point
inference traffic directly to `host.docker.internal:11434`.

Native Ollama SDKs or non-OpenAI-compatible protocols must use MLflow
Ollama autologging, MLflow SDK tracing, OpenTelemetry to MLflow `/v1/traces`,
or a repository-owned protocol adapter. This provides observability but does
not automatically provide Gateway routing, budgets, or guardrails. An
uninstrumented direct Ollama inference client is not an accepted service.

## Hindsight migration

Hindsight changes its chat and embedding base URLs to
`http://mlflow:5000/gateway/mlflow/v1`, and uses respectively
`ollama-chat-default` and `ollama-embedding-default` as model values. Its
existing native `ollama pull`, `/api/tags`, and `/api/version` operations stay
direct host management/readiness operations and are not inference traces.

Hindsight joins `local-ai-services` as an external network. Its existing
`dotfiles-memory` network and independent lifecycle remain unchanged. The
implementation must live-test both chat and embedding request shapes through
the Gateway before claiming the migration complete.

## Failure behavior

Gateway-backed inference is fail-closed by default: if MLflow is unavailable,
the request fails instead of silently bypassing MLflow. Existing service
retries and degraded behavior may continue, but must not add an untraced
fallback. Any emergency bypass is explicit, opt-in, and visibly logged.

Errors distinguish host Ollama readiness, MLflow Gateway availability, and
consumer-service failures.

## Operator interface

The root Taskfile includes `taskfiles/mlflow/taskfile.yml`:

- `task mlflow:up`: validate Docker, create the shared network, start MLflow,
  wait for health, and apply defaults.
- `task mlflow:configure`: apply endpoint definitions idempotently.
- `task mlflow:down`: stop MLflow without deleting data or the network.
- `task mlflow:status`: show container and Gateway endpoint state.
- `task mlflow:logs`: follow MLflow logs.
- `task mlflow:verify`: exercise chat and embedding, then verify traces.

## Testing and acceptance

Deterministic checks cover Compose config, pinned image, loopback port,
persistent mounts, host mapping, `local-ai-services`, endpoint uniqueness and
tracing settings, Taskfile public tasks, and Hindsight's Gateway URLs.
Offline configuration tests prove idempotency without contacting Ollama.

Live acceptance starts MLflow, applies endpoints, sends chat and embedding
requests, confirms host Ollama was reached, confirms both traces exist, starts
Hindsight and runs its existing health/persistence acceptance, then verifies
Hindsight traces and SQLite persistence after restart. Container liveness or a
direct Ollama response alone is not tracing proof.

## Non-goals

- Replacing native host Ollama with an Ollama container.
- Routing model pulls or readiness probes through MLflow.
- Adding PostgreSQL before local concurrency or sharing requires it.
- Automatically instrumenting external repositories not owned here.
- Adding remote exposure or authentication to the initial local deployment.

## References

- <https://mlflow.org/docs/latest/genai/governance/ai-gateway/endpoints/model-providers/>
- <https://mlflow.org/docs/latest/api_reference/rest-api.html>
- <https://mlflow.org/docs/latest/self-hosting/architecture/tracking-server/>
- <https://mlflow.org/docs/latest/genai/tracing/opentelemetry/ingest/>
