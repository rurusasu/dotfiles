#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/sh/hindsight.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	BIN="$BATS_TEST_TMPDIR/bin"
	LOG="$BATS_TEST_TMPDIR/commands.log"
	COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
	COMPOSE="$COMPOSE_DIR/compose.yml"
	LEGACY_CONTAINER_STATE="$BATS_TEST_TMPDIR/legacy-container.state"
	LEGACY_CONTAINER_RUNNING_STATE="$BATS_TEST_TMPDIR/legacy-container-running.state"
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
if [[ ${1:-} == container && ${2:-} == inspect ]]; then
	legacy_exists="${HINDSIGHT_LEGACY_CONTAINER_EXISTS:-0}"
	if [[ -f $LEGACY_CONTAINER_STATE ]]; then
		legacy_exists="$(<"$LEGACY_CONTAINER_STATE")"
	fi
	[[ ${*: -1} == hermes-hindsight && $legacy_exists == 1 ]] || exit $?
	if [[ ${3:-} == --format ]]; then
		legacy_running="${HINDSIGHT_LEGACY_CONTAINER_RUNNING:-1}"
		if [[ -f $LEGACY_CONTAINER_RUNNING_STATE ]]; then
			legacy_running="$(<"$LEGACY_CONTAINER_RUNNING_STATE")"
		fi
		[[ $legacy_running == 1 ]] && printf 'true\n' || printf 'false\n'
	fi
	exit 0
fi
if [[ ${1:-} == rm && ${2:-} == hermes-hindsight && ${HINDSIGHT_LEGACY_RM_FAIL:-0} == 1 ]]; then
	exit 42
fi
if [[ ${1:-} == rm && ${2:-} == hermes-hindsight ]]; then
	printf '0\n' >"$LEGACY_CONTAINER_STATE"
	printf '0\n' >"$LEGACY_CONTAINER_RUNNING_STATE"
fi
if [[ ${1:-} == start && ${2:-} == hermes-hindsight ]]; then
	printf '1\n' >"$LEGACY_CONTAINER_STATE"
	printf '1\n' >"$LEGACY_CONTAINER_RUNNING_STATE"
fi
if [[ ${1:-} == stop && ${2:-} == hermes-hindsight ]]; then
	printf '0\n' >"$LEGACY_CONTAINER_RUNNING_STATE"
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
	export HOME="$TEST_HOME" LOG LEGACY_CONTAINER_STATE LEGACY_CONTAINER_RUNNING_STATE PATH="$BIN:$PATH"
	export HINDSIGHT_API_READY_ATTEMPTS=1 HINDSIGHT_API_READY_DELAY_SECONDS=0
}

@test "first independent start copies legacy Hermes memory and retires its container" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.hermes/hindsight/cache"
	printf 'retained-memory\n' >"$HOME/.hermes/hindsight/pg0/memory"
	printf 'reranker-cache\n' >"$HOME/.hermes/hindsight/cache/model"
	export HINDSIGHT_LEGACY_CONTAINER_EXISTS=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	[ "$(cat "$HOME/.local/share/hindsight/pg0/memory")" = retained-memory ]
	[ "$(cat "$HOME/.local/share/hindsight/cache/model")" = reranker-cache ]
	[ "$(cat "$HOME/.hermes/hindsight/pg0/memory")" = retained-memory ]
	[ "$(cat "$HOME/.local/share/hindsight/.legacy-migration-source")" = "$HOME/.hermes/hindsight" ]
	grep -Fxq 'docker stop hermes-hindsight' "$LOG"
	grep -Fxq 'docker rm hermes-hindsight' "$LOG"
	run grep -Fxq 'docker start hermes-hindsight' "$LOG"
	[ "$status" -ne 0 ]
	pull_line="$(grep -nFx 'ollama pull qwen3-embedding:0.6b' "$LOG" | cut -d: -f1)"
	config_line="$(grep -nFx "docker compose -f $COMPOSE config --quiet" "$LOG" | cut -d: -f1)"
	image_pull_line="$(grep -nFx "docker compose -f $COMPOSE pull hindsight" "$LOG" | cut -d: -f1)"
	stop_line="$(grep -nFx 'docker stop hermes-hindsight' "$LOG" | tail -n 1 | cut -d: -f1)"
	start_line="$(grep -nFx "docker compose -f $COMPOSE up -d --force-recreate --remove-orphans hindsight" "$LOG" | cut -d: -f1)"
	health_line="$(grep -nF 'curl --fail --silent --show-error' "$LOG" | cut -d: -f1)"
	retire_line="$(grep -nFx 'docker rm hermes-hindsight' "$LOG" | cut -d: -f1)"
	[ "$pull_line" -lt "$stop_line" ]
	[ "$config_line" -lt "$stop_line" ]
	[ "$image_pull_line" -lt "$stop_line" ]
	[ "$stop_line" -lt "$start_line" ]
	[ "$health_line" -lt "$retire_line" ]

	: >"$LOG"
	run "$SCRIPT" up "$COMPOSE"
	[ "$status" -eq 0 ]
	! grep -Fq 'docker stop hermes-hindsight' "$LOG"
}

@test "model preparation failure leaves the legacy service untouched" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.hermes/hindsight/cache"
	printf 'retained-memory\n' >"$HOME/.hermes/hindsight/pg0/memory"
	export HINDSIGHT_LEGACY_CONTAINER_EXISTS=1 HINDSIGHT_OLLAMA_PULL_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	grep -Fxq 'ollama pull qwen3.6:35b' "$LOG"
	run grep -Fxq 'docker stop hermes-hindsight' "$LOG"
	[ "$status" -ne 0 ]
	run grep -Fxq 'docker rm hermes-hindsight' "$LOG"
	[ "$status" -ne 0 ]
}

@test "image pull failure uses a cached image when the registry is unavailable" {
	export HINDSIGHT_COMPOSE_PULL_FAIL=1 HINDSIGHT_LOCAL_IMAGE_EXISTS=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	grep -Fxq "docker compose -f $COMPOSE pull hindsight" "$LOG"
	grep -Fxq 'docker image inspect nginx:1.29-alpine' "$LOG"
	grep -Fxq "docker compose -f $COMPOSE up -d --force-recreate --remove-orphans hindsight" "$LOG"
}

@test "failed legacy migration restarts the container it stopped" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.hermes/hindsight/cache"
	printf 'retained-memory\n' >"$HOME/.hermes/hindsight/pg0/memory"
	export HINDSIGHT_LEGACY_CONTAINER_EXISTS=1
	cat >"$BIN/cp" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
	chmod +x "$BIN/cp"

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	grep -Fxq 'docker stop hermes-hindsight' "$LOG"
	grep -Fxq 'docker start hermes-hindsight' "$LOG"
	run grep -Fq 'docker rm hermes-hindsight' "$LOG"
	[ "$status" -ne 0 ]
	[ "$(cat "$HOME/.hermes/hindsight/pg0/memory")" = retained-memory ]
}

@test "failed legacy migration preserves a previously stopped container" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.hermes/hindsight/cache"
	printf 'retained-memory\n' >"$HOME/.hermes/hindsight/pg0/memory"
	export HINDSIGHT_LEGACY_CONTAINER_EXISTS=1 HINDSIGHT_LEGACY_CONTAINER_RUNNING=0
	cat >"$BIN/cp" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
	chmod +x "$BIN/cp"

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	run grep -Fxq 'docker stop hermes-hindsight' "$LOG"
	[ "$status" -ne 0 ]
	run grep -Fxq 'docker start hermes-hindsight' "$LOG"
	[ "$status" -ne 0 ]
}

@test "failed independent startup restores the legacy service" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.hermes/hindsight/cache"
	printf 'retained-memory\n' >"$HOME/.hermes/hindsight/pg0/memory"
	export HINDSIGHT_LEGACY_CONTAINER_EXISTS=1 HINDSIGHT_COMPOSE_UP_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	grep -Fxq 'docker stop hermes-hindsight' "$LOG"
	grep -Fxq "docker compose -f $COMPOSE stop hindsight" "$LOG"
	grep -Fxq 'docker start hermes-hindsight' "$LOG"
	! grep -Fxq 'docker rm hermes-hindsight' "$LOG"
}

@test "failed replacement quarantines its snapshot and recopies restored legacy memory on retry" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.hermes/hindsight/cache"
	printf 'before-restoration\n' >"$HOME/.hermes/hindsight/pg0/memory"
	export HINDSIGHT_LEGACY_CONTAINER_EXISTS=1 HINDSIGHT_COMPOSE_UP_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	[ ! -e "$HOME/.local/share/hindsight" ]
	quarantine="$(find "$HOME/.local/share" -maxdepth 1 -type d -name 'hindsight.failed-cutover.*' -print -quit)"
	[ -n "$quarantine" ]
	[ "$(cat "$quarantine/pg0/memory")" = before-restoration ]

	printf 'after-restoration\n' >"$HOME/.hermes/hindsight/pg0/memory"
	: >"$LOG"
	export HINDSIGHT_COMPOSE_UP_FAIL=0
	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	[ "$(cat "$HOME/.local/share/hindsight/pg0/memory")" = after-restoration ]
}

@test "completed migration retries legacy retirement before honoring its marker" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.hermes/hindsight/cache"
	printf 'retained-memory\n' >"$HOME/.hermes/hindsight/pg0/memory"
	export HINDSIGHT_LEGACY_CONTAINER_EXISTS=1 HINDSIGHT_LEGACY_RM_FAIL=1

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	[ -f "$HOME/.local/share/hindsight/.legacy-migration-source" ]
	grep -Fxq "docker compose -f $COMPOSE up -d --force-recreate --remove-orphans hindsight" "$LOG"

	: >"$LOG"
	export HINDSIGHT_LEGACY_RM_FAIL=0
	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -eq 0 ]
	run grep -Fxq 'docker stop hermes-hindsight' "$LOG"
	[ "$status" -ne 0 ]
	grep -Fxq 'docker rm hermes-hindsight' "$LOG"
	retire_line="$(grep -nFx 'docker rm hermes-hindsight' "$LOG" | cut -d: -f1)"
	start_line="$(grep -nFx "docker compose -f $COMPOSE up -d --force-recreate --remove-orphans hindsight" "$LOG" | cut -d: -f1)"
	[ "$start_line" -lt "$retire_line" ]
}

@test "legacy migration refuses to overwrite an independent memory database" {
	mkdir -p "$HOME/.hermes/hindsight/pg0" "$HOME/.local/share/hindsight/pg0"
	printf 'legacy\n' >"$HOME/.hermes/hindsight/pg0/memory"
	printf 'current\n' >"$HOME/.local/share/hindsight/pg0/memory"

	run "$SCRIPT" up "$COMPOSE"

	[ "$status" -ne 0 ]
	[[ "$output" == *'both contain data'* ]]
	[ "$(cat "$HOME/.local/share/hindsight/pg0/memory")" = current ]
	! grep -Fq 'docker stop hindsight' "$LOG"
	! grep -Fq 'ollama pull' "$LOG"
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
