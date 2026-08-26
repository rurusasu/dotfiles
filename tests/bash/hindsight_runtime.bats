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
		'HINDSIGHT_API_LLM_MODEL=qwen3.6:35b' \
		'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=qwen3-embedding:0.6b' \
		>"$COMPOSE_DIR/hindsight.env"
	: >"$LOG"

	cat >"$BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$LOG"
if [[ ${1:-} == container && ${2:-} == inspect ]]; then
	[[ ${3:-} == hermes-hindsight && ${HINDSIGHT_LEGACY_CONTAINER_EXISTS:-0} == 1 ]]
fi
EOF
	cat >"$BIN/ollama" <<'EOF'
#!/usr/bin/env bash
printf 'ollama %s\n' "$*" >>"$LOG"
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
	stop_line="$(grep -nFx 'docker stop hermes-hindsight' "$LOG" | cut -d: -f1)"
	start_line="$(grep -nFx "docker compose -f $COMPOSE up -d hindsight" "$LOG" | cut -d: -f1)"
	[ "$stop_line" -lt "$start_line" ]

	: >"$LOG"
	run "$SCRIPT" up "$COMPOSE"
	[ "$status" -eq 0 ]
	! grep -Fq 'docker stop hermes-hindsight' "$LOG"
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
	grep -Fxq "docker compose -f $COMPOSE config --quiet" "$LOG"
	grep -Fxq "docker compose -f $COMPOSE up -d hindsight" "$LOG"
	[ -d "$HOME/.local/share/hindsight/pg0" ]
	[ -d "$HOME/.local/share/hindsight/cache" ]
	! grep -qi hermes "$LOG"
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
	! grep -Eq '^ollama ' "$LOG"
}

@test "duplicate model assignment fails before pulling or starting" {
	printf '%s\n' \
		'HINDSIGHT_API_LLM_MODEL=qwen3.6:35b' \
		'HINDSIGHT_API_LLM_MODEL=duplicate' \
		'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=qwen3-embedding:0.6b' \
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
