#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/sh/hindsight.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	BIN="$BATS_TEST_TMPDIR/bin"
	LOG="$BATS_TEST_TMPDIR/commands.log"
	COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
	COMPOSE="$COMPOSE_DIR/compose.yml"
	mkdir -p "$TEST_HOME" "$BIN" "$COMPOSE_DIR"
	printf 'services: {}\n' >"$COMPOSE"
	printf '%s\n' \
		'HINDSIGHT_API_LLM_MODEL=ollama-chat-default' \
		'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=ollama-embedding-default' \
		'HINDSIGHT_OLLAMA_LLM_MODEL=qwen3.6:35b' \
		'HINDSIGHT_OLLAMA_EMBEDDING_MODEL=qwen3-embedding:0.6b' \
		>"$COMPOSE_DIR/hindsight.env"
	: >"$LOG"

	cat >"$BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$LOG"
if [[ ${1:-} == compose && ${4:-} == stop && ${5:-} == hindsight && ${HINDSIGHT_COMPOSE_STOP_FAIL:-0} == 1 ]]; then
	exit 46
fi
if [[ ${1:-} == compose && ${*: -5} == 'up -d --force-recreate --remove-orphans hindsight' && ${HINDSIGHT_COMPOSE_UP_FAIL:-0} == 1 ]]; then
	exit 43
fi
if [[ ${1:-} == compose && ${4:-} == pull && ${5:-} == hindsight && ${HINDSIGHT_COMPOSE_PULL_FAIL:-0} == 1 ]]; then
	exit 45
fi
if [[ ${1:-} == compose && ${4:-} == config && ${5:-} == --images ]]; then
	printf 'nginx:1.29-alpine\n'
	exit 0
fi
if [[ ${1:-} == image && ${2:-} == inspect && ${HINDSIGHT_LOCAL_IMAGE_EXISTS:-0} != 1 ]]; then
	exit 1
fi
EOF
cat >"$BIN/ollama" <<'EOF'
#!/usr/bin/env bash
printf 'ollama %s\n' "$*" >>"$LOG"
if [[ ${1:-} == pull && ${HINDSIGHT_OLLAMA_PULL_FAIL:-0} == 1 ]]; then
	exit 44
fi
EOF
	cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$LOG"
printf '%s\n' "${HINDSIGHT_HEALTH_RESPONSE:-{\"status\":\"healthy\",\"database\":\"connected\"}}"
EOF
	chmod +x "$BIN/docker" "$BIN/ollama" "$BIN/curl"
	export HOME="$TEST_HOME" LOG PATH="$BIN:$PATH"
	export HINDSIGHT_API_READY_ATTEMPTS=1 HINDSIGHT_API_READY_DELAY_SECONDS=0
}

@test "startup uses current memory without importing leftover Hermes data" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.local/share/hindsight/pg0"
	printf 'legacy-memory\n' >"$HOME/.hermes/hindsight/pg0/memory"
	printf 'current-memory\n' >"$HOME/.local/share/hindsight/pg0/memory"

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	[ "$(cat "$HOME/.local/share/hindsight/pg0/memory")" = current-memory ]
	[ "$(cat "$HOME/.hermes/hindsight/pg0/memory")" = legacy-memory ]
	[ ! -e "$HOME/.local/share/hindsight/.legacy-migration-source" ]
	! grep -Fq 'hermes-hindsight' "$LOG"
}

@test "startup failure stops only current service and preserves migrated memory and marker" {
	mkdir -p "$HOME/.local/share/hindsight/pg0"
	printf 'current-memory\n' >"$HOME/.local/share/hindsight/pg0/memory"
	printf '%s\n' "$HOME/.hermes/hindsight" >"$HOME/.local/share/hindsight/.legacy-migration-source"
	export HINDSIGHT_COMPOSE_UP_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	grep -Fxq "docker compose -f $COMPOSE stop hindsight" "$LOG"
	[ "$(cat "$HOME/.local/share/hindsight/pg0/memory")" = current-memory ]
	[ "$(cat "$HOME/.local/share/hindsight/.legacy-migration-source")" = "$HOME/.hermes/hindsight" ]
	! grep -Fq 'hermes-hindsight' "$LOG"
}

@test "model preparation failure never starts the service" {
	export HINDSIGHT_OLLAMA_PULL_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	grep -Fxq 'ollama pull qwen3.6:35b' "$LOG"
	! grep -Fq 'up -d' "$LOG"
	! grep -Fq 'stop hindsight' "$LOG"
}

@test "image pull failure uses a cached image when the registry is unavailable" {
	export HINDSIGHT_COMPOSE_PULL_FAIL=1 HINDSIGHT_LOCAL_IMAGE_EXISTS=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	grep -Fxq "docker compose -f $COMPOSE pull hindsight" "$LOG"
	grep -Fxq 'docker image inspect nginx:1.29-alpine' "$LOG"
	grep -Fxq "docker compose -f $COMPOSE up -d --force-recreate --remove-orphans hindsight" "$LOG"
}

@test "independent up pulls two models creates private data and starts only Hindsight" {
	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	grep -Fxq 'ollama pull qwen3.6:35b' "$LOG"
	grep -Fxq 'ollama pull qwen3-embedding:0.6b' "$LOG"
	! grep -Fxq 'ollama pull ollama-chat-default' "$LOG"
	! grep -Fxq 'ollama pull ollama-embedding-default' "$LOG"
	grep -Fxq "docker compose -f $COMPOSE config --quiet" "$LOG"
	grep -Fxq "docker compose -f $COMPOSE up -d --force-recreate --remove-orphans hindsight" "$LOG"
	[ -d "$HOME/.local/share/hindsight/pg0" ]
	[ -d "$HOME/.local/share/hindsight/cache" ]
	! grep -Eq '^docker (stop|start|rm) hermes-hindsight$' "$LOG"
}

@test "acceptance can inject an offline Ollama executable explicitly" {
	cat >"$BIN/offline-ollama" <<'EOF'
#!/usr/bin/env bash
printf 'offline-ollama %s\n' "$*" >>"$LOG"
EOF
	chmod +x "$BIN/offline-ollama"
	export DOTFILES_HINDSIGHT_OLLAMA_EXECUTABLE="$BIN/offline-ollama"

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	grep -Fxq 'offline-ollama pull qwen3.6:35b' "$LOG"
	grep -Fxq 'offline-ollama pull qwen3-embedding:0.6b' "$LOG"
	! grep -Fxq 'offline-ollama pull ollama-chat-default' "$LOG"
	! grep -Fxq 'offline-ollama pull ollama-embedding-default' "$LOG"
	! grep -Eq '^ollama ' "$LOG"
}

@test "duplicate model assignment fails before pulling or starting" {
	printf '%s\n' \
		'HINDSIGHT_API_LLM_MODEL=ollama-chat-default' \
		'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=ollama-embedding-default' \
		'HINDSIGHT_OLLAMA_LLM_MODEL=qwen3.6:35b' \
		'HINDSIGHT_OLLAMA_LLM_MODEL=duplicate' \
		'HINDSIGHT_OLLAMA_EMBEDDING_MODEL=qwen3-embedding:0.6b' \
		>"$COMPOSE_DIR/hindsight.env"

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	[[ "$output" == *'must occur exactly once'* ]]
	[ ! -s "$LOG" ]
}

@test "health verification requires database connectivity" {
	export HINDSIGHT_HEALTH_RESPONSE='{"status":"healthy","database":"disconnected"}'

	run "$SCRIPT" verify "$COMPOSE"

	[ "$status" -ne 0 ]
	[[ "$output" == *'did not become ready'* ]]
}

@test "readiness failure stops the service and returns failure" {
	export HINDSIGHT_HEALTH_RESPONSE='{"status":"healthy","database":"disconnected"}'

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	[[ "$output" == *'did not become ready'* ]]
	grep -Fxq "docker compose -f $COMPOSE stop hindsight" "$LOG"
}

@test "failed cleanup preserves the startup failure and reports the stop failure" {
	export HINDSIGHT_COMPOSE_UP_FAIL=1 HINDSIGHT_COMPOSE_STOP_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 43 ]
	[[ "$output" == *'Unable to stop'* ]]
}

@test "image pull without a cached image fails before startup" {
	export HINDSIGHT_COMPOSE_PULL_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	[[ "$output" == *'no cached image'* ]]
	! grep -Fq 'up -d' "$LOG"
}
