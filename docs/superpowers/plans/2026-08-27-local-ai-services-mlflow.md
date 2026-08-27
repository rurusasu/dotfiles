# Local AI Services MLflow Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent, local MLflow AI Gateway for all Ollama-backed services, migrate Hindsight through it, and provide a repeatable onboarding contract for future services.

**Architecture:** MLflow runs as an independent pinned Compose service on the externally named `local-ai-services` network. It is the only container allowed to call host Ollama through `host.docker.internal`; Docker clients use the OpenAI-compatible Gateway URL and stable logical endpoint names. MLflow tracking metadata and traces use a bind-mounted SQLite backend, while a repository-owned endpoint manifest is reconciled through the documented Gateway REST API.

**Tech Stack:** Docker Compose, MLflow `v3.12.0` image pinned by digest, MLflow Gateway REST API, SQLite, Python 3 standard library plus the pinned image's YAML parser, go-task, Bash, PowerShell, unittest, Bats.

**Spec:** `docs/superpowers/specs/2026-08-27-local-ai-services-mlflow-design.md`

## Global Constraints

- Use the shared Docker network name `local-ai-services`; keep Hindsight's existing `dotfiles-memory` network and independent lifecycle.
- Publish MLflow only on `127.0.0.1:5000`; container clients use `http://mlflow:5000/gateway/mlflow/v1`.
- Pin the MLflow image to released version `v3.12.0` and the digest resolved from the registry; never use `latest`.
- Use `sqlite:////mlflow/mlflow.db` with host data root `${MLFLOW_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/mlflow}` and retain data across `down`/restart.
- Keep model pulls and Ollama readiness probes direct to host Ollama; route every model inference through MLflow or an explicitly documented MLflow instrumentation path.
- Store no API keys, prompts, responses, or trace payloads in Git; keep the local MLflow data root outside the repository.
- Gateway inference is fail-closed by default; no automatic direct-Ollama fallback may be introduced.
- Preserve unrelated dirty files in the primary checkout and make implementation commits only in `/Users/ktome1995/Program/dotfiles/.worktrees/local-ai-mlflow`.

---

## File Map

- Create `docker/mlflow/compose.yml`: isolated MLflow tracking/Gateway runtime, persistent bind mounts, healthcheck, loopback port, and shared network attachment.
- Create `docker/mlflow/endpoints.yml`: secret-free source of truth for stable chat and embedding endpoint definitions.
- Create `docker/mlflow/configure.py`: typed, idempotent Gateway REST reconciler with redacted errors.
- Create `docker/mlflow/verify.py`: container-side chat, embedding, and trace acceptance probe.
- Modify `docker/mlflow/compose.yml`: mount the Gateway control scripts and manifest read-only at their stable container paths.
- Create `docker/mlflow/tests/test_configure.py`: offline fake-server tests for reconciliation, idempotency, and failure handling.
- Create `taskfiles/mlflow/taskfile.yml`: public `mlflow:*` operator tasks and their preconditions/dependencies.
- Modify `Taskfile.yml`: shared MLflow Compose variable and included taskfile.
- Modify `taskfiles/hindsight/taskfile.yml`: make `hindsight:up` start/configure MLflow first.
- Modify `docker/hindsight/compose.yml`: attach Hindsight to the external `local-ai-services` network while retaining `memory`.
- Modify `docker/hindsight/hindsight.env`: use Gateway URLs and logical endpoint names; add separate native model names for direct pull preparation.
- Modify `scripts/sh/hindsight.sh`: pull the native model variables, not Gateway endpoint names.
- Modify `scripts/powershell/hindsight.ps1`: apply the same model-management split on Windows.
- Modify `docker/hermes-agent/bootstrap/tests/test_compose_contract.py`: update the Hindsight and shared-network contract assertions.
- Create or modify focused `tests/python/test_mlflow_contract.py`: validate manifest, Compose, Hindsight routing, and task contracts without Docker inference.
- Create `tests/bash/mlflow_task_contract.bats`: validate public task names and command wiring using the repository's existing Taskfile test style.
- Modify `ci/path-routing.json`: route MLflow, Hindsight migration, operator task, and focused test changes to contract plus platform/Hermes checks.
- Modify `ci/bootstrap-path-routing.json`: route Docker MLflow and related bootstrap contract changes to all supported platform bootstrap outputs.
- Modify `docs/architecture.md`: document the shared Gateway boundary, network, persistence, and migration conditions for PostgreSQL.
- Modify `docs/hermes-agent/hindsight-memory.md`: document Gateway-based inference, direct-only model preparation, verification, privacy, retention, and future-service onboarding.
- Create `docs/mlflow/local-ai-services.md`: operator runbook and service onboarding contract.

## Task 1: Add the pinned MLflow Compose runtime and endpoint manifest

**Files:**

- Create: `docker/mlflow/compose.yml`
- Create: `docker/mlflow/endpoints.yml`
- Create: `tests/python/test_mlflow_contract.py`

**Interfaces:**

- Produces Compose service `mlflow`, network `local-ai-services`, container path `/mlflow/mlflow.db`, and manifest endpoints `ollama-chat-default` and `ollama-embedding-default`.
- The manifest records `provider`, `model_name`, `api_base`, `capability`, and `usage_tracking`; it contains no secret values or prompt data.

- [ ] **Step 1: Write failing static contract tests.**

  Add tests that parse the Compose YAML and manifest and assert:

  ```python
  self.assertTrue(compose["services"]["mlflow"]["image"].startswith("ghcr.io/mlflow/mlflow:v3.12.0@sha256:"))
  self.assertEqual(compose["services"]["mlflow"]["ports"], ["127.0.0.1:${MLFLOW_PORT:-5000}:5000"])
  self.assertEqual(compose["networks"]["local-ai-services"], {"name": "local-ai-services", "external": True})
  self.assertEqual(manifest["endpoints"][0]["name"], "ollama-chat-default")
  self.assertEqual(manifest["endpoints"][1]["name"], "ollama-embedding-default")
  self.assertTrue(all("secret" not in json.dumps(item).lower() for item in manifest["endpoints"]))
  ```

- [ ] **Step 2: Run the focused tests and verify they fail for missing files.**

  Run:

  ```bash
  python3 -m unittest tests/python/test_mlflow_contract.py -v
  ```

  Expected: FAIL because the MLflow Compose file and manifest do not exist yet.

- [ ] **Step 3: Resolve and record the released image digest.**

  Run:

  ```bash
  docker buildx imagetools inspect ghcr.io/mlflow/mlflow:v3.12.0
  ```

  Use the registry digest returned for the multi-platform manifest in `docker/mlflow/compose.yml`; do not copy a platform-specific child digest and do not use `latest`.

- [ ] **Step 4: Implement the Compose service.**

  Configure `mlflow` with:

  ```yaml
  command:
    - mlflow
    - server
    - --host
    - 0.0.0.0
    - --port
    - "5000"
    - --backend-store-uri
    - sqlite:////mlflow/mlflow.db
    - --default-artifact-root
    - /mlflow/artifacts
  ```

  Bind-mount `${MLFLOW_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/mlflow}` to `/mlflow`, add `host.docker.internal:host-gateway`, publish only the loopback port, add a Python HTTP healthcheck for `/health`, and attach the service to the external `local-ai-services` network. The Compose file must not declare an Ollama service.

- [ ] **Step 5: Implement the endpoint manifest.**

  Define exactly these initial logical endpoints:

  ```yaml
  endpoints:
    - name: ollama-chat-default
      provider: ollama
      model_name: qwen3.6:35b
      api_base: http://host.docker.internal:11434
      capability: chat
      usage_tracking: true
    - name: ollama-embedding-default
      provider: ollama
      model_name: qwen3-embedding:0.6b
      api_base: http://host.docker.internal:11434
      capability: embeddings
      usage_tracking: true
  ```

  Keep the manifest limited to non-secret configuration and stable endpoint names.

- [ ] **Step 6: Run deterministic Compose and contract checks.**

  Run:

  ```bash
  python3 -m unittest tests/python/test_mlflow_contract.py -v
  docker compose -f docker/mlflow/compose.yml config --quiet
  ```

  Expected: all focused tests pass and Compose exits with status 0.

- [ ] **Step 7: Commit the runtime foundation.**

  ```bash
  git add docker/mlflow/compose.yml docker/mlflow/endpoints.yml tests/python/test_mlflow_contract.py
  git commit -m "feat: add local MLflow gateway runtime"
  ```

## Task 2: Implement idempotent Gateway configuration and live verification

**Files:**

- Create: `docker/mlflow/configure.py`
- Create: `docker/mlflow/verify.py`
- Create: `docker/mlflow/tests/test_configure.py`
- Modify: `docker/mlflow/compose.yml`

**Interfaces:**

- `GatewayClient.request(method: str, path: str, payload: dict[str, object] | None) -> dict[str, object]` performs JSON REST calls and raises a typed error containing status and a redacted response.
- `reconcile_manifest(base_url: str, manifest_path: Path) -> None` creates or updates the named secret, model definitions, and endpoints without duplicate resources.
- `verify_gateway(base_url: str, chat_endpoint: str, embedding_endpoint: str, experiment_name: str) -> None` sends both request shapes and confirms traces are searchable.

- [ ] **Step 1: Write offline fake-server tests for the REST contract.**

  Build a `ThreadingHTTPServer` fixture that implements the pinned MLflow Gateway API paths for secret, model definition, endpoint, and trace search operations. Test that one reconciliation creates each resource, a second reconciliation performs lookups and updates without creating duplicates, the endpoint has `usage_tracking: true`, and an HTTP 4xx/5xx error includes the path/status but never prints `api_key` or secret values.

- [ ] **Step 2: Run the reconciler tests to establish the failing baseline.**

  ```bash
  python3 -m unittest docker/mlflow/tests/test_configure.py -v
  ```

  Expected: FAIL because the client and reconciliation functions are absent.

- [ ] **Step 3: Implement the typed HTTP client.**

  Use `urllib.request` and `json` so the host environment does not need an additional package. Normalize the base URL, send `Content-Type: application/json`, parse JSON responses, and convert `HTTPError`/`URLError` to the typed error. Redact values for keys named `api_key`, `value`, `secret`, `token`, `prompt`, and `response` before including server payloads in an exception.

- [ ] **Step 4: Implement manifest reconciliation against the documented API.**

  Load `endpoints.yml` with the YAML library available in the pinned MLflow image. Reconcile in this order: secret `ollama-local`, each provider model definition, then each logical endpoint. Use the documented `/api/3.0/mlflow/gateway/...` paths and resource names to find existing objects. Configure the Ollama secret with the non-sensitive compatibility key `api_key=ollama`; put the manifest's `api_base` in the provider auth configuration; never serialize the secret manifest to disk or print it.

  The endpoint model configuration must point to the reconciled model definition, set primary linkage/weight, preserve the logical endpoint name, and enable `usage_tracking`. If an existing named resource differs, update it; if it matches, leave it unchanged. Treat a missing resource as create, not as an error.

- [ ] **Step 5: Mount the control-plane files in Compose.**

  Add read-only bind mounts from `./configure.py`, `./verify.py`, and `./endpoints.yml` to `/opt/mlflow/configure.py`, `/opt/mlflow/verify.py`, and `/opt/mlflow/endpoints.yml`. Keep the files outside the persistent `/mlflow` data mount so runtime data cannot overwrite repository configuration.

- [ ] **Step 6: Implement the verification probe.**

  Send one OpenAI-compatible chat request to `/gateway/mlflow/v1/chat/completions` with model `ollama-chat-default`, and one embedding request to `/gateway/mlflow/v1/embeddings` with model `ollama-embedding-default`. Use deterministic short input and a low token limit. Query MLflow trace search for the resulting request window and require evidence of both endpoint names. Exit nonzero with separate messages for Gateway availability, upstream Ollama failure, response-shape failure, and missing traces.

- [ ] **Step 7: Run offline tests and validate the script inside the pinned image.**

  ```bash
  python3 -m unittest docker/mlflow/tests/test_configure.py -v
  docker compose -f docker/mlflow/compose.yml run --rm --no-deps mlflow python /opt/mlflow/configure.py --help
  docker compose -f docker/mlflow/compose.yml run --rm --no-deps mlflow python /opt/mlflow/verify.py --help
  ```

  Expected: all fake-server tests pass and both scripts start in the actual image with the required YAML/runtime dependencies.

- [ ] **Step 8: Commit the Gateway control plane.**

  ```bash
  git add docker/mlflow/configure.py docker/mlflow/verify.py docker/mlflow/tests/test_configure.py
  git commit -m "feat: reconcile and verify MLflow gateway endpoints"
  ```

## Task 3: Add cross-platform operator tasks and shared-network ordering

**Files:**

- Create: `taskfiles/mlflow/taskfile.yml`
- Modify: `Taskfile.yml`
- Modify: `taskfiles/hindsight/taskfile.yml`
- Create: `tests/bash/mlflow_task_contract.bats`
- Modify: `tests/python/test_mlflow_contract.py`

**Interfaces:**

- Provides `task mlflow:up`, `task mlflow:configure`, `task mlflow:down`, `task mlflow:status`, `task mlflow:logs`, and `task mlflow:verify` on Linux, macOS, WSL, and Windows.
- `mlflow:up` starts the service, waits for health, and then invokes `mlflow:configure`; `hindsight:up` depends on `mlflow:up` and never bypasses it.

- [ ] **Step 1: Add failing Taskfile contract tests.**

  Assert that the root Taskfile includes `taskfiles/mlflow/taskfile.yml`, the six public task names exist, `mlflow:up` has a Docker precondition, and Hindsight's start task contains a dependency on `mlflow:up`. Assert that `mlflow:down` uses `stop` and does not remove the data volume or shared network.

- [ ] **Step 2: Run the Taskfile contract tests.**

  ```bash
  python3 -m unittest tests/python/test_mlflow_contract.py -v
  bats tests/bash/mlflow_task_contract.bats
  ```

  Expected: FAIL until the include, taskfile, and dependency are added.

- [ ] **Step 3: Implement the MLflow taskfile.**

  Define `MLFLOW_COMPOSE_FILE: docker/mlflow/compose.yml` in the taskfile's local vars. Use `docker compose ... up -d --wait mlflow` for the startup wait, then call `docker compose ... exec -T mlflow python /opt/mlflow/configure.py --base-url http://127.0.0.1:5000 --manifest /opt/mlflow/endpoints.yml`; use the read-only mounts established by Task 2. `mlflow:configure` must require a running healthy container, `mlflow:down` must stop only `mlflow`, `status` must show Compose status plus endpoint names, `logs` must remain interactive, and `verify` must invoke `/opt/mlflow/verify.py`.

- [ ] **Step 4: Include the taskfile and wire Hindsight startup.**

  Add the shared Compose variable and flattened `mlflow` include to `Taskfile.yml`. Add `deps: - task: mlflow:up` to `hindsight:up`; do not make Hindsight depend on a removed or renamed task.

- [ ] **Step 5: Run task listing and contract validation.**

  ```bash
  task --list
  python3 -m unittest tests/python/test_mlflow_contract.py -v
  bats tests/bash/mlflow_task_contract.bats
  ```

  Expected: all public MLflow tasks are listed and tests pass.

- [ ] **Step 6: Commit operator integration.**

  ```bash
  git add Taskfile.yml taskfiles/mlflow/taskfile.yml taskfiles/hindsight/taskfile.yml tests/bash/mlflow_task_contract.bats tests/python/test_mlflow_contract.py
  git commit -m "feat: add MLflow operator tasks"
  ```

## Task 4: Migrate Hindsight inference without breaking direct model preparation

**Files:**

- Modify: `docker/hindsight/hindsight.env`
- Modify: `docker/hindsight/compose.yml`
- Modify: `scripts/sh/hindsight.sh`
- Modify: `scripts/powershell/hindsight.ps1`
- Modify: `docker/hermes-agent/bootstrap/tests/test_compose_contract.py`
- Modify: `tests/bash/hindsight_runtime.bats`
- Modify: `tests/bash/hindsight_service.bats`

**Interfaces:**

- Hindsight inference uses `http://mlflow:5000/gateway/mlflow/v1`, with `HINDSIGHT_API_LLM_MODEL=ollama-chat-default` and `HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=ollama-embedding-default`.
- Direct preparation uses `HINDSIGHT_OLLAMA_LLM_MODEL=qwen3.6:35b` and `HINDSIGHT_OLLAMA_EMBEDDING_MODEL=qwen3-embedding:0.6b`; these are the only values passed to `ollama pull`.

- [ ] **Step 1: Update failing Hindsight contract expectations.**

  Change the existing compose/env tests to assert the Gateway URLs, logical endpoint model values, the two new native model variables, and both networks:

  ```python
  self.assertEqual(hindsight["networks"], ["memory", "local-ai-services"])
  self.assertEqual(environment["HINDSIGHT_API_LLM_BASE_URL"], "http://mlflow:5000/gateway/mlflow/v1")
  self.assertEqual(environment["HINDSIGHT_API_LLM_MODEL"], "ollama-chat-default")
  self.assertEqual(environment["HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL"], "ollama-embedding-default")
  ```

  Add assertions that the shell and PowerShell preparation commands use the native variables and never call `ollama pull ollama-chat-default` or `ollama pull ollama-embedding-default`.

- [ ] **Step 2: Run the focused Hindsight tests to confirm the expected failures.**

  ```bash
  python3 -m unittest docker/hermes-agent/bootstrap/tests/test_compose_contract.py -v
  bats tests/bash/hindsight_runtime.bats tests/bash/hindsight_service.bats
  ```

  Expected: FAIL on the old host-Ollama inference URLs, model values, network list, and preparation variable names.

- [ ] **Step 3: Change Hindsight environment and Compose networking.**

  Set chat and embedding base URLs to `http://mlflow:5000/gateway/mlflow/v1`, set the request model fields to the two logical endpoint names, retain the provider/API-key compatibility settings required by Hindsight, and add the two native model variables for preparation. Declare `local-ai-services` as an external network and attach Hindsight to it in addition to the existing `memory` network.

- [ ] **Step 4: Change both preparation adapters.**

  In `scripts/sh/hindsight.sh` and `scripts/powershell/hindsight.ps1`, read `HINDSIGHT_OLLAMA_LLM_MODEL` and `HINDSIGHT_OLLAMA_EMBEDDING_MODEL` for direct `ollama pull` and readiness checks. Continue using `ollama list`, `/api/tags`, and `/api/version` against host Ollama only for model management/readiness. Keep error messages distinct for host Ollama and MLflow Gateway failures.

- [ ] **Step 5: Run deterministic Hindsight and Compose checks.**

  ```bash
  python3 -m unittest docker/hermes-agent/bootstrap/tests/test_compose_contract.py -v
  bats tests/bash/hindsight_runtime.bats tests/bash/hindsight_service.bats
  docker compose -f docker/mlflow/compose.yml config --quiet
  docker compose -f docker/hindsight/compose.yml config --quiet
  ```

  Expected: all tests pass and both Compose projects resolve with the external shared network declaration.

- [ ] **Step 6: Commit the Hindsight migration.**

  ```bash
  git add docker/hindsight/hindsight.env docker/hindsight/compose.yml scripts/sh/hindsight.sh scripts/powershell/hindsight.ps1 docker/hermes-agent/bootstrap/tests/test_compose_contract.py tests/bash/hindsight_runtime.bats tests/bash/hindsight_service.bats
  git commit -m "feat: route Hindsight inference through MLflow"
  ```

## Task 5: Document the future-service onboarding contract and local operations

**Files:**

- Create: `docs/mlflow/local-ai-services.md`
- Modify: `docs/architecture.md`
- Modify: `docs/hermes-agent/hindsight-memory.md`

**Interfaces:**

- The runbook defines the service registration fields: service identifier, capability, logical endpoint, connection mode, network requirement, and live trace verification command.
- Documentation names the approved modes: OpenAI-compatible Gateway, MLflow Ollama autologging/SDK tracing, OpenTelemetry to MLflow `/v1/traces`, or a repository-owned protocol adapter.

- [ ] **Step 1: Write the operator runbook.**

  Document:

  ```text
  task mlflow:up
  task mlflow:status
  task mlflow:verify
  task mlflow:logs
  task mlflow:down
  ```

  Explain endpoint-name stability, host-native URL `http://127.0.0.1:5000/gateway/mlflow/v1`, Docker URL `http://mlflow:5000/gateway/mlflow/v1`, loopback exposure, persistent path, SQLite backup/retention, and the exact PostgreSQL migration triggers from the spec.

- [ ] **Step 2: Document mandatory onboarding and fail-closed behavior.**

  Show a minimal Docker service configuration using `MLFLOW_GATEWAY_URL` and `MLFLOW_MODEL`, require the service to join `local-ai-services`, prohibit direct `host.docker.internal:11434` inference URLs, and state that an emergency bypass must be explicit, opt-in, and visibly logged. Explain that external repositories are not modified automatically; their provider configuration must be onboarded deliberately.

- [ ] **Step 3: Update architecture and Hindsight documents.**

  Replace claims that Hindsight inference directly targets host Ollama with the two-layer model-management/inference description. Keep direct pulls and readiness probes documented as non-traced operations, add MLflow trace verification, and preserve the existing `dotfiles-memory` lifecycle explanation.

- [ ] **Step 4: Review documentation against the spec.**

  Search for stale direct-inference claims:

  ```bash
  rg -n "host\.docker\.internal:11434/v1|HINDSIGHT_API_LLM_MODEL|HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL|dotfiles-memory" docs docker/hindsight scripts
  ```

  Each remaining direct Ollama reference must be a model-management/readiness reference or an explicitly identified non-migrated external-service boundary.

- [ ] **Step 5: Commit the documentation.**

  ```bash
  git add docs/mlflow/local-ai-services.md docs/architecture.md docs/hermes-agent/hindsight-memory.md
  git commit -m "docs: define local AI services onboarding"
  ```

## Task 6: Route CI checks and complete deterministic validation

**Files:**

- Modify: `ci/path-routing.json`
- Modify: `ci/bootstrap-path-routing.json`
- Modify: `tests/python/test_detect_ci_changes.py` if routing fixtures require explicit coverage
- Modify: `tests/bash/taskfile_test_routing.bats` if taskfile routing assertions require the new paths

**Interfaces:**

- Changes under `docker/mlflow/**`, `taskfiles/mlflow/**`, `docs/mlflow/**`, and MLflow-related Hindsight/operator tests trigger the existing contract and platform outputs that can execute Compose contracts.
- MLflow changes do not create an unimplemented CI output name; they use the repository's existing `contract`, `linux`, `darwin`, `wsl`, `windows`, and `hermes` outputs as applicable.

- [ ] **Step 1: Add failing routing assertions.**

  Extend the routing tests with representative paths `docker/mlflow/compose.yml`, `docker/mlflow/configure.py`, `taskfiles/mlflow/taskfile.yml`, and `docs/mlflow/local-ai-services.md`, asserting that each maps to contract checks and that runtime/Hindsight changes retain platform and Hermes coverage.

- [ ] **Step 2: Run the routing tests.**

  ```bash
  python3 -m unittest tests/python/test_detect_ci_changes.py -v
  bats tests/bash/taskfile_test_routing.bats
  ```

  Expected: FAIL for the new MLflow paths until both routing manifests and their tests are updated.

- [ ] **Step 3: Update both routing manifests.**

  Add MLflow Docker and taskfile patterns to the same contract/platform rules used by Hindsight and its Taskfile. Add documentation and focused Python/Bats test patterns to the contract rule. Keep the existing broad fallback behavior unchanged.

- [ ] **Step 4: Run routing, formatting, and all focused tests.**

  ```bash
  python3 -m unittest tests/python/test_detect_ci_changes.py tests/python/test_mlflow_contract.py docker/mlflow/tests/test_configure.py -v
  bats tests/bash/taskfile_test_routing.bats tests/bash/mlflow_task_contract.bats tests/bash/hindsight_runtime.bats tests/bash/hindsight_service.bats
  nix fmt -- --check
  git diff --check
  ```

  Expected: all deterministic tests pass, formatting reports no changes, and the diff has no whitespace errors.

- [ ] **Step 5: Commit routing and test coverage.**

  ```bash
  git add ci/path-routing.json ci/bootstrap-path-routing.json tests/python/test_detect_ci_changes.py tests/bash/taskfile_test_routing.bats
  git commit -m "ci: route local AI gateway changes"
  ```

## Task 7: Run live acceptance and review the final diff

**Files:**

- Verify all files changed by Tasks 1-6; make a source change only if a failed acceptance check identifies a concrete defect.

- [ ] **Step 1: Confirm local prerequisites without changing host model state.**

  ```bash
  docker info
  ollama version
  ollama list
  ```

  If Docker or Ollama is unavailable, record the exact unavailable boundary and complete all deterministic checks; do not claim live tracing proof.

- [ ] **Step 2: Start and configure MLflow.**

  ```bash
  task mlflow:up
  task mlflow:status
  ```

  Confirm the container is healthy, the shared network exists, and both logical endpoints are listed.

- [ ] **Step 3: Prove Gateway upstream access and trace creation.**

  ```bash
  task mlflow:verify
  ```

  Require successful chat and embedding responses, evidence that host Ollama served both requests, and two searchable MLflow traces. A healthy container or direct `ollama` response is insufficient.

- [ ] **Step 4: Start Hindsight through the dependency chain and run existing acceptance.**

  ```bash
  task hindsight:up
  task hindsight:verify
  ```

  Confirm Hindsight reaches MLflow over `local-ai-services`, retains/recalls through the existing persistence acceptance, and creates MLflow traces for both chat and embedding work.

- [ ] **Step 5: Prove persistence across a controlled restart.**

  Run `task mlflow:down`, `task mlflow:up`, and `task mlflow:verify`; confirm the endpoint definitions and prior trace metadata remain available in the bind-mounted SQLite data root. Do not remove the data directory or network.

- [ ] **Step 6: Review status and final diff.**

  ```bash
  git status --short
  git diff main...HEAD --stat
  git diff main...HEAD --check
  git log --oneline main..HEAD
  ```

  Verify only the intended worktree commits/files are present, the primary checkout's unrelated `flake.lock`, `.claude/`, and `.codex/hooks/claude_permission_policy.py` changes remain untouched, and unresolved issues distinguish deterministic from live validation.
