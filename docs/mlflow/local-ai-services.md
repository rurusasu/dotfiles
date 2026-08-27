# Local AI Services Onboarding and Operations

This runbook defines the local contract for MLflow-backed AI services. The
Gateway is the default inference boundary for services that speak an
OpenAI-compatible protocol. A service is not onboarded merely because its
container is healthy: its configured path and a live trace must be verified.

## Service registration contract

Every new local-AI service must register the following fields before it is
enabled:

| Field                           | Required meaning                                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Service identifier              | Stable repository/service name, unique within this local deployment                                                       |
| Capability                      | `chat`, `embeddings`, or another explicitly supported capability                                                          |
| Logical endpoint                | Stable MLflow Gateway endpoint name, such as `ollama-chat-default`; clients must not use the provider's native model name |
| Connection mode                 | One of the approved modes below                                                                                           |
| Network requirement             | The Docker network(s) required to reach the selected endpoint                                                             |
| Live trace verification command | A reproducible command that sends a request and proves the resulting MLflow trace                                         |

Approved connection modes are:

1. OpenAI-compatible Gateway, using MLflow Gateway endpoint names.
2. MLflow Ollama autologging/SDK tracing for a native Ollama SDK.
3. OpenTelemetry to the MLflow `/v1/traces` ingest endpoint.
4. A repository-owned protocol adapter that records the equivalent MLflow
   trace evidence.

The mode must match the client's protocol. An uninstrumented direct Ollama
inference client is not an approved mode. The observability modes provide
trace evidence but do not automatically provide Gateway routing, budgets, or
guardrails.

## Gateway client configuration

The endpoint names are capability-oriented and stable. The provider model may
change behind an endpoint without requiring every consumer configuration to
change. The current endpoints are:

| Capability       | Logical endpoint           | Initial provider model |
| ---------------- | -------------------------- | ---------------------- |
| Chat/completions | `ollama-chat-default`      | `qwen3.6:35b`          |
| Embeddings       | `ollama-embedding-default` | `qwen3-embedding:0.6b` |

For a Docker service, use the service name on `local-ai-services`:

```yaml
services:
  future-service:
    environment:
      MLFLOW_GATEWAY_URL: http://mlflow:5000/gateway/mlflow/v1
      MLFLOW_MODEL: ollama-chat-default
    networks:
      - local-ai-services

networks:
  local-ai-services:
    external: true
    name: local-ai-services
```

The service must join `local-ai-services`. It must not use
`host.docker.internal:11434` as an inference URL. Only MLflow contacts native
host Ollama directly for the configured provider. Host-native clients use the
same Gateway path through:

```text
http://127.0.0.1:5000/gateway/mlflow/v1
```

MLflow itself listens on `0.0.0.0:5000` inside its container, but Compose
publishes it only on the host loopback address (`127.0.0.1:5000`). It is not a
remote service. The Docker URL above is reachable only from a client attached
to the shared network.

External repositories are not modified automatically. Their provider
configuration, connection mode, network attachment, and trace verification
must be deliberately onboarded in that repository or through an explicitly
owned adapter.

## Fail-closed rule

Gateway-backed inference fails when MLflow is unavailable; it must not silently
fall back to direct host Ollama. Existing consumer retries and degraded
behavior may remain, provided they do not turn an inference request into an
untraced request. An emergency bypass requires all of the following:

- explicit opt-in by the operator or service configuration;
- a clearly named, reviewed bypass setting; and
- visible logging of activation and each bypassed request path.

## Operator tasks

The normal lifecycle is:

```text
task mlflow:up
task mlflow:status
task mlflow:configure
task mlflow:verify
task mlflow:logs
task mlflow:down
```

`task mlflow:up` validates Docker, creates `local-ai-services` if absent,
starts the pinned MLflow service, waits for `/health`, and configures the
manifest. `task mlflow:configure` can be rerun to reconcile endpoint
definitions without duplicates. `status` shows the container and configured
endpoint names. `logs` follows the last 100 MLflow log lines. `down` stops
only MLflow and preserves both its data and the shared network.

`task mlflow:verify` sends deterministic chat and embedding requests through
the Gateway and searches the resulting MLflow trace window for both logical
endpoint IDs. A healthy container, a successful direct Ollama response, or a
successful Gateway response without matching trace evidence is not sufficient.
Use this as the live trace verification command in a service registration.

## Runtime data, backup, and retention

The default host runtime root is:

```text
${MLFLOW_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/mlflow}
```

It is bind-mounted to `/mlflow` and contains the SQLite backend
`mlflow.db` and MLflow artifacts. This is private local runtime data, not Git
content. Repository-controlled files such as `docker/mlflow/endpoints.yml`,
`configure.py`, and `verify.py` are mounted separately and read-only.

Stop MLflow before backup so the SQLite file and artifacts are consistent:

```text
task mlflow:down
```

Archive `mlflow.db` and `artifacts/` from the configured data root, preserve
file ownership and restrictive access controls, and encrypt the archive. Trace
metadata may contain prompts, responses, token metadata, and latency. Define a
retention period appropriate for that sensitivity, delete expired archives
securely, and keep only the minimum local history needed for operations. Do
not commit the data root or copy it into a profile repository.

SQLite is the initial backend for one local user and low-to-moderate
concurrency. Migrate to PostgreSQL when any of these exact triggers occurs:

- multiple users share the server;
- sustained concurrent writes produce database-lock or latency failures; or
- the service becomes an always-on shared deployment.

Until a trigger occurs, do not add PostgreSQL solely for future possibility.
When a trigger occurs, preserve a verified SQLite backup, plan the migration as
a gated change, and re-run Gateway configuration and live trace verification
after cutover.

## Direct model management boundary

Native Ollama operations remain separate from traced inference. Model pulls,
`/api/tags`, and `/api/version` readiness probes use the host-native Ollama
service directly; they do not create MLflow inference traces. Consumers use
the stable Gateway endpoint names for inference after those native models are
ready.
