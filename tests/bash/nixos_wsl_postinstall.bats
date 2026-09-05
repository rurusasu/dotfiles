#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/nixos-wsl-postinstall.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	USER_HOME="$TEST_HOME/alice"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	NIXOS_ARGV_CAPTURE="$BATS_TEST_TMPDIR/nixos-rebuild.argv"
	NIX_EVAL_CAPTURE="$BATS_TEST_TMPDIR/nix-eval.result"
	REAL_NIX="$(command -v nix || true)"

	mkdir -p "$USER_HOME" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$NIXOS_ARGV_CAPTURE"
	: >"$NIX_EVAL_CAPTURE"

	export HOME="$TEST_HOME"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG NIXOS_ARGV_CAPTURE NIX_EVAL_CAPTURE REAL_NIX REPO_ROOT USER_HOME
	export DOTFILES_SKIP_HERDR_INSTALL=1

	write_stub id '
case "$*" in
  "-u") printf "0\n" ;;
  "-u alice") printf "4242\n" ;;
  "-g alice") printf "4343\n" ;;
  "-gn alice") printf "alicegrp\n" ;;
  "alice") exit 0 ;;
  *) exit 2 ;;
esac
'
	write_stub getent '
if [[ ${1:-} == passwd && ${2:-} == alice ]]; then
  printf "alice:x:4242:4343:Alice:%s:/bin/bash\n" "$USER_HOME"
  exit 0
fi
exit 2
'
	write_stub uname '
case "${1:-}" in
  -m) printf "x86_64\n" ;;
  -s) printf "Linux\n" ;;
  *) exit 2 ;;
esac
'
	write_stub runuser '
printf "runuser %s\n" "$*" >>"$COMMAND_LOG"
while (($# > 0)); do
  if [[ $1 == -- ]]; then
    shift
    break
  fi
  shift
done
exec "$@"
'
	write_stub chown '
printf "chown %s\n" "$*" >>"$COMMAND_LOG"
'
	write_stub nixos-rebuild '
printf "%s\n" "$@" >"$NIXOS_ARGV_CAPTURE"
printf "nixos-rebuild user=%s home=%s uid=%s gid=%s group=%s\n" \
  "${DOTFILES_USER:-}" "${DOTFILES_HOME:-}" "${DOTFILES_UID:-}" \
  "${DOTFILES_GID:-}" "${DOTFILES_GROUP:-}" >>"$COMMAND_LOG"

if [[ -n ${REAL_NIX:-} ]]; then
  nix_eval_args=()
  for arg in "$@"; do
    [[ $arg == --impure ]] && nix_eval_args+=("$arg")
  done

	if ((${#nix_eval_args[@]} == 1)); then
		nix_eval_expr=$(cat <<NIX_EXPR
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        config = flake.nixosConfigurations.nixos.config;
        homeManager = builtins.getAttr "home-manager" config;
      in
        if config.wsl.defaultUser != "alice" then
          throw "wsl.defaultUser is not alice"
        else if !builtins.hasAttr "alice" config.users.users then
          throw "users.users is missing alice"
        else if !builtins.hasAttr "alice" homeManager.users then
          throw "home-manager.users is missing alice"
        else
          "ok"

NIX_EXPR
		)
		"$REAL_NIX" eval "${nix_eval_args[@]}" --raw --no-write-lock-file --expr "$nix_eval_expr" >"$NIX_EVAL_CAPTURE"
  else
    printf "nix eval skipped: nixos-rebuild argv has no --impure\n" >>"$COMMAND_LOG"
  fi
fi
'
}

write_stub() {
	local name="$1"
	local body="$2"
	cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
	chmod +x "$STUB_BIN/$name"
}

@test "postinstall preserves the selected WSL user and runs an impure flake rebuild" {
	RUN_REPO_DIR="$BATS_TEST_TMPDIR/repo"

	run bash "$INSTALLER" \
		--user alice \
		--sync-mode link \
		--sync-source "$REPO_ROOT" \
		--repo-dir "$RUN_REPO_DIR" \
		--sync-back none \
		--skip-flake-update

	[ "$status" -eq 0 ]
	grep -Fqx "nixos-rebuild user=alice home=$USER_HOME uid=4242 gid=4343 group=alicegrp" "$COMMAND_LOG"

	expected_args=(switch --flake "path:$REPO_ROOT#nixos" --impure)
	mapfile -t actual_args <"$NIXOS_ARGV_CAPTURE"
	[ "${#actual_args[@]}" -eq "${#expected_args[@]}" ]
	for index in "${!expected_args[@]}"; do
		[ "${actual_args[$index]}" = "${expected_args[$index]}" ]
	done

	if [[ -n $REAL_NIX ]]; then
		[ "$(<"$NIX_EVAL_CAPTURE")" = ok ]
	fi
}
