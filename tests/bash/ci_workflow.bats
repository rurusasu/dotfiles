#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	WORKFLOW="$REPO_ROOT/.github/workflows/ci-nix.yml"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
	unset DEFINITION_HASH CAN_PUBLISH DOCKER_EXIT DOCKER_RESULT
	export PATH="$STUB_BIN:$PATH" GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
	export RUNNER_TEMP="$BATS_TEST_TMPDIR" GITHUB_WORKSPACE="$BATS_TEST_TMPDIR"
	cd "$REPO_ROOT"
}

workflow_step() {
	JOB="$2" STEP="$3" yq -er \
		'(.jobs[strenv(JOB)] // .runs).steps[] | select(.name == strenv(STEP)) | .run' "$1"
}

write_stub() {
	{
		printf '#!/usr/bin/env bash\nset -euo pipefail\n'
		cat
	} >"$STUB_BIN/$1"
	chmod +x "$STUB_BIN/$1"
}

run_script() {
	run bash --noprofile --norc -e -o pipefail -c "$1"
}

@test "Linux build installs declared hardware without identity inference" {
	script=$(workflow_step "$WORKFLOW" linux-build 'Build Linux configurations and checks')
	export INVOCATION_LOG="$BATS_TEST_TMPDIR/nix-args" INSTALL_LOG="$BATS_TEST_TMPDIR/install-args"
	unset DOTFILES_USER DOTFILES_HOME
	write_stub nix <<'EOF'
[[ ! -v DOTFILES_USER && ! -v DOTFILES_HOME ]]
printf '%s\0' "$@" >"$INVOCATION_LOG"
EOF
	write_stub install <<'EOF'
printf '%s\0' "$@" >"$INSTALL_LOG"
EOF
	run_script "$script"
	[ "$status" -eq 0 ]
	printf '%s\0' -D -m 0644 "$GITHUB_WORKSPACE/nix/tests/fixtures/hardware-configuration.nix" \
		/etc/nixos/hardware-configuration.nix >"$BATS_TEST_TMPDIR/expected"
	cmp "$INSTALL_LOG" "$BATS_TEST_TMPDIR/expected"
	tr '\0' '\n' <"$INVOCATION_LOG" >"$BATS_TEST_TMPDIR/build-args"
	[ "$(head -2 "$BATS_TEST_TMPDIR/build-args")" = $'build\n--impure' ]
	grep -Fxq '.#nixosConfigurations.linux.config.system.build.toplevel' "$BATS_TEST_TMPDIR/build-args"
	grep -Fxq '.#homeConfigurations.x86_64-linux.activationPackage' "$BATS_TEST_TMPDIR/build-args"
}

@test "WSL prebuild exports zstd transport and fails closed" {
	script=$(workflow_step "$WORKFLOW" wsl-prebuild 'Build the WSL system closure and export a local cache')
	export STORE_PATH=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-hermes
	write_stub nix <<'EOF'
case "$1" in
--version) echo 'nix boundary double' ;;
build)
	[[ " $* " == *' .#nixosConfigurations.nixos.config.system.build.toplevel '* ]]
	printf '%s\n' "$STORE_PATH" ;;
copy)
	[[ $# == 4 && $2 == --to && $4 == "$STORE_PATH" && $3 == file:///*'?compression=zstd' ]]
	((COPY_EXIT == 0)) || exit "$COPY_EXIT"
	cache=${3#file://}
	[[ ${cache#*\?} == compression=zstd ]]
	cache=${cache%\?compression=zstd}
	mkdir -p "$cache/nar"
	printf cache >"$cache/nar/private.nar.zst"
	printf 'StorePath: %s\nURL: %s\nReferences: %s\n' "$STORE_PATH" "$NAR_URL" "$NAR_REFS" \
		>"$cache/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.narinfo" ;;
path-info) [[ $2 == --recursive ]]; printf '%s\n' "$STORE_PATH" ;;
*) exit 64 ;;
esac
EOF
	write_stub nix-store <<'EOF'
[[ "$1 $2 $3 $4" == '--store https://cache.nixos.org --check-validity --print-invalid' ]]
shift 4
printf '%s\n' "$@"
EOF
	for case in success native traversal missing closure; do
		export RUNNER_TEMP="$BATS_TEST_TMPDIR/$case/container runner temp"
		export DOTFILES_CI_BINARY_CACHE="$RUNNER_TEMP/persistent-cache"
		export COPY_EXIT=0 NAR_URL=nar/private.nar.zst NAR_REFS=''
		expected=1 diagnostic=''
		case "$case" in
		success) expected=0 ;;
		native)
			COPY_EXIT=47
			expected=47
			;;
		traversal)
			NAR_URL=../outside.nar
			diagnostic='Invalid NAR location'
			;;
		missing)
			NAR_URL=nar/missing.nar
			diagnostic='Missing NAR payload'
			;;
		closure)
			NAR_REFS=outside-closure
			diagnostic='Incomplete reference closure'
			;;
		esac
		mkdir -p "$DOTFILES_CI_BINARY_CACHE"
		: >"$GITHUB_OUTPUT"
		run_script "$script"
		[ "$status" -eq "$expected" ]
		if ((expected)); then
			[[ $output == *"$diagnostic"* ]]
			[ ! -s "$GITHUB_OUTPUT" ]
			[ ! -e "$RUNNER_TEMP/wsl-nix-cache-artifact/wsl-nix-cache.tar" ]
		else
			artifact=$(sed -n 's/^artifact-dir=//p' "$GITHUB_OUTPUT")
			[[ $artifact == "$RUNNER_TEMP/"* ]]
			[ "$(ls -1 "$artifact")" = $'wsl-nix-cache.tar\nwsl-system-paths.txt' ]
			[ "$(cat "$artifact/wsl-system-paths.txt")" = "$STORE_PATH" ]
			tar -tf "$artifact/wsl-nix-cache.tar" >"$BATS_TEST_TMPDIR/archive-list"
			grep -Fxq './nar/private.nar.zst' "$BATS_TEST_TMPDIR/archive-list"
			grep -Fxq './public-paths.txt' "$BATS_TEST_TMPDIR/archive-list"
		fi
		if ((COPY_EXIT == 0)); then
			[ -f "$DOTFILES_CI_BINARY_CACHE/nar/private.nar.zst" ]
		fi
	done
}

@test "CI authentication follows Nix home and keeps tokens private" {
	write_stub getent <<'EOF'
printf 'fixture:x:0:0:Fixture:%s:/bin/bash\n' "$FALLBACK_HOME"
EOF
	write_stub nix <<'EOF'
case "$*" in
'config show access-tokens') field=access-tokens ;;
'config show substituters') field=extra-substituters ;;
'config show trusted-public-keys') field=extra-trusted-public-keys ;;
*) exit 64 ;;
esac
grep "^$field = " "$EXPECTED_CONFIG/nix/bootstrap-ci.conf" | cut -d= -f2-
EOF
	for use_xdg in true false; do
		for wsl in true false; do
			for owned_home in true false; do
				fixture="$BATS_TEST_TMPDIR/$use_xdg-$wsl-$owned_home"
				export FALLBACK_HOME="$fixture/passwd-home" HOME="$fixture/missing-home"
				export EXPECTED_CONFIG="$FALLBACK_HOME/.config" GITHUB_ENV="$fixture/github-env"
				export GIT_CONFIG_SYSTEM="$fixture/gitconfig" GITHUB_WORKSPACE="$fixture/checkout"
				export GITHUB_TOKEN=fixture-token-not-a-real-secret
				mkdir -p "$FALLBACK_HOME"
				unset XDG_CONFIG_HOME NIX_CONFIG NIX_USER_CONF_FILES
				if [[ $owned_home == true ]]; then
					HOME=$FALLBACK_HOME
					if [[ $use_xdg == true ]]; then EXPECTED_CONFIG="$fixture/xdg"; fi
				fi
				if [[ $use_xdg == true ]]; then export XDG_CONFIG_HOME="$EXPECTED_CONFIG"; fi
				args=()
				if [[ $wsl == true ]]; then
					args=(--wsl)
					unset GITHUB_WORKSPACE
				fi
				for attempt in 1 2; do
					run bash "$REPO_ROOT/scripts/sh/configure-bootstrap-ci-nix.sh" "${args[@]}"
					[ "$status" -eq 0 ]
					[[ $output != *"$GITHUB_TOKEN"* ]]
				done
				if [[ $owned_home == true ]]; then
					[ ! -e "$GITHUB_ENV" ]
				else
					printf 'HOME=%s\nXDG_CONFIG_HOME=\nHOME=%s\nXDG_CONFIG_HOME=\n' \
						"$FALLBACK_HOME" "$FALLBACK_HOME" >"$fixture/expected-env"
					cmp "$GITHUB_ENV" "$fixture/expected-env"
				fi
				secret_file="$EXPECTED_CONFIG/nix/bootstrap-ci.conf"
				[ "$(stat -c %a "$secret_file" 2>/dev/null || stat -f %Lp "$secret_file")" = 600 ]
				[ "$(grep -Fc "include $secret_file" "$EXPECTED_CONFIG/nix/nix.conf")" -eq 1 ]
				if [[ $wsl == true ]]; then
					[ ! -e "$GIT_CONFIG_SYSTEM" ]
					grep -Fxq 'max-jobs = 2' "$secret_file"
				else
					run git config --system --get-all safe.directory
					[ "$status" -eq 0 ]
					[ "$output" = "$GITHUB_WORKSPACE" ]
					! grep -Fq "$GITHUB_TOKEN" "$GIT_CONFIG_SYSTEM"
				fi
			done
		done
	done
}

image_step() {
	export GITHUB_REPOSITORY=RuruSasu/Dotfiles DEFINITION_HASH="${DEFINITION_HASH-$(printf 'a%.0s' {1..64})}"
	export CAN_PUBLISH="${CAN_PUBLISH-true}" DOCKER_EXIT="${DOCKER_EXIT-0}"
	export DOCKER_RESULT="${DOCKER_RESULT-sha256:$(printf 'b%.0s' {1..64})}"
	write_stub docker <<'EOF'
[[ "$1 $2 $3" == 'buildx imagetools inspect' ]]
printf '%s\n' "$DOCKER_RESULT"
exit "$DOCKER_EXIT"
EOF
	: >"$GITHUB_OUTPUT"
	script=$(workflow_step "$WORKFLOW" ci-tools "$1")
	run_script "$script"
}

@test "existing tools image is reused without a build" {
	image_step 'Select image for the tool definition'
	[ "$status" -eq 0 ]
	[ "$(cat "$GITHUB_OUTPUT")" = "tag=ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools:$DEFINITION_HASH"$'\nbuild=false' ]
}

@test "missing tools image is built only with publish authority" {
	export DOCKER_EXIT=1
	for CAN_PUBLISH in true false; do
		export CAN_PUBLISH
		image_step 'Select image for the tool definition'
		if [[ $CAN_PUBLISH == true ]]; then
			[ "$status" -eq 0 ]
			grep -Fxq 'build=true' "$GITHUB_OUTPUT"
		else
			[ "$status" -eq 1 ]
			! grep -Fxq 'build=true' "$GITHUB_OUTPUT"
		fi
	done
}

@test "missing definition hash fails before selecting an image" {
	export DEFINITION_HASH=''
	image_step 'Select image for the tool definition'
	[ "$status" -ne 0 ]
	[ ! -s "$GITHUB_OUTPUT" ]
}

@test "tools consumers receive only a valid immutable reference" {
	export IMAGE=ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools:tag
	for DOCKER_RESULT in "sha256:$(printf 'b%.0s' {1..64})" invalid; do
		export DOCKER_RESULT
		image_step 'Resolve immutable image reference'
		if [[ $DOCKER_RESULT == invalid ]]; then
			[ "$status" -eq 1 ]
			[ ! -s "$GITHUB_OUTPUT" ]
		else
			[ "$status" -eq 0 ]
			[ "$(cat "$GITHUB_OUTPUT")" = "image=ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools@$DOCKER_RESULT" ]
		fi
	done
}

@test "Windows source verification rejects invalid WSLg paths XML and render failures" {
	command -v pwsh >/dev/null || skip 'requires PowerShell to execute the Windows workflow step'
	workflow_step "$REPO_ROOT/.github/workflows/ci-chezmoi.yml" source 'Verify the managed Windows targets' >"$BATS_TEST_TMPDIR/verify.ps1"
	mkdir -p "$GITHUB_WORKSPACE/chezmoi" "$GITHUB_WORKSPACE/nix/modules/fonts"
	export CANONICAL_XML=$'<?xml version="1.0"?>\n<fontconfig><dir>/fixture/fonts</dir></fontconfig>\n'
	printf '%s' "$CANONICAL_XML" >"$GITHUB_WORKSPACE/nix/modules/fonts/wsl-fontconfig.conf"
	write_stub chezmoi <<'EOF'
while (($#)); do
	case "$1" in
	--override-data) data=$2; shift ;;
	managed|execute-template) command=$1 ;;
	--include) kind=$2; shift ;;
	--file) file=$2; shift ;;
	esac
	shift
done
if [[ $RENDER_CASE == windows-home ]]; then
	jq -e '.chezmoi == {os:"windows",homeDir:"C:/Users/ci"}' <<<"$data" >/dev/null
fi
if [[ $command == managed ]]; then
	if [[ $kind == files ]]; then
		printf '%s\n' .config/dotfiles/wslg-fontconfig.conf .config/git/config .config/wezterm/wezterm.lua \
			.wslgconfig AppData/Local/superfile/config.toml Documents/PowerShell/Microsoft.PowerShell_profile.ps1
	else
		printf '%s\n' .chezmoiscripts/deploy/keybindings/sync_wsl_keybindings.ps1 \
			.chezmoiscripts/deploy/terminals/install_udev_gothic_nf.ps1
	fi
else
	[[ $RENDER_CASE != render-error ]] || exit 41
	if [[ $file == *dot_wslgconfig.tmpl ]]; then
		mount=/mnt/c/Users/ci
		if [[ $RENDER_CASE == bad-path ]]; then mount=/mnt//oot; fi
		printf '[system-distro-env]\nFONTCONFIG_FILE=%s/.config/dotfiles/wslg-fontconfig.conf\n' "$mount"
	else
		case "$RENDER_CASE" in
		malformed-xml) printf '<fontconfig>' ;;
		different-xml) printf '<fontconfig><dir>/other</dir></fontconfig>' ;;
		*) printf '%s' "$CANONICAL_XML" ;;
		esac
	fi
fi
EOF
	for RENDER_CASE in windows-home bad-path malformed-xml different-xml render-error; do
		export RENDER_CASE
		run pwsh -NoLogo -NoProfile -NonInteractive -File "$BATS_TEST_TMPDIR/verify.ps1"
		if [[ $RENDER_CASE == windows-home ]]; then [ "$status" -eq 0 ]; else [ "$status" -eq 1 ]; fi
	done
}

@test "bootstrap aggregate accepts no work and rejects missing required jobs" {
	script=$(workflow_step "$WORKFLOW" complete 'Verify routed job results')
	for changes in '' CHANGES_RESULT=failure LINUX_BUILD_REQUIRED=true NIX_REQUIRED=true \
		BASH_REQUIRED=true 'BASH_REQUIRED=true BASH_RESULT=failure' 'BASH_REQUIRED=true BASH_RESULT=success' \
		BASH_RESULT=success \
		'TOOLS_REQUIRED=true TOOLS_RESULT=success NIX_REQUIRED=true NIX_RESULT=success LINUX_BUILD_REQUIRED=true LINUX_BUILD_RESULT=success' \
		WINDOWS_REQUIRED=true 'WINDOWS_REQUIRED=true WINDOWS_INSTALLER_RESULT=success' WINDOWS_INSTALLER_RESULT=success DARWIN_RESULT=success; do
		while read -r variable; do
			if [[ $variable == *_RESULT ]]; then export "$variable=skipped"; else export "$variable=false"; fi
		done < <(grep -oE '\$\{[A-Z_]+\}' <<<"$script" | tr -d '${}' | sort -u)
		export CHANGES_RESULT=success
		for assignment in $changes; do export "$assignment"; done
		run_script "$script"
		case "$changes" in
		'' | 'BASH_REQUIRED=true BASH_RESULT=success' | 'TOOLS_REQUIRED=true '* | 'WINDOWS_REQUIRED=true WINDOWS_INSTALLER_RESULT=success') [ "$status" -eq 0 ] ;;
		*) [ "$status" -eq 1 ] ;;
		esac
	done
}

git_fixture() {
	mkdir -p "$1"
	cd "$1"
	git init -q
	git config user.email ci@example.test
	git config user.name 'CI Test'
	printf 'fixture\n' >README.md
	git add .
	git commit -qm initial
}

commit_nix() {
	mkdir -p nix
	printf '#!/bin/sh\n' >nix/example.nix
	git add .
	git commit -qm 'add nix config'
}

detect_changes() {
	: >"$GITHUB_OUTPUT"
	local script
	script=$(workflow_step "$REPO_ROOT/.github/actions/detect-ci-changes/action.yml" '' 'Classify changed paths')
	run env BASE_SHA="$1" HEAD_SHA="$2" RUN_ALL="${3:-false}" GITHUB_EVENT_NAME="${4:-push}" \
		bash --noprofile --norc -e -o pipefail -c "$script"
}

assert_categories() {
	local name expected
	for name in nix chezmoi other linux darwin wsl windows; do
		expected=false
		if [[ " $* " == *" $name "* ]]; then expected=true; fi
		grep -Fxq "$name=$expected" "$GITHUB_OUTPUT"
	done
	[ "$(wc -l <"$GITHUB_OUTPUT")" -eq 7 ]
}

@test "change detector classifies Git paths and rejects invalid revisions" {
	git_fixture "$BATS_TEST_TMPDIR/revisions"
	base=$(git rev-parse HEAD)
	commit_nix
	head=$(git rev-parse HEAD)
	for revision in "$base" 0000000000000000000000000000000000000000; do
		detect_changes "$revision" "$head"
		[ "$status" -eq 0 ]
		assert_categories nix linux darwin wsl
		{
			if [[ $revision == 0000000000000000000000000000000000000000 ]]; then printf 'README.md\0'; fi
			printf 'nix/example.nix\0'
		} >"$BATS_TEST_TMPDIR/expected"
		cmp "$RUNNER_TEMP/ci-changed-paths" "$BATS_TEST_TMPDIR/expected"
	done
	detect_changes missing-base "$head"
	[ "$status" -ne 0 ]
	[ ! -s "$GITHUB_OUTPUT" ]
	detect_changes "$base" missing-head
	[ "$status" -ne 0 ]
	[ ! -s "$GITHUB_OUTPUT" ]
	index=0
	while IFS='|' read -r categories paths; do
		index=$((index + 1))
		git_fixture "$BATS_TEST_TMPDIR/paths-$index"
		base=$(git rev-parse HEAD)
		IFS=';' read -r -a files <<<"$paths"
		for path in "${files[@]}"; do
			path=${path//\\n/$'\n'}
			mkdir -p "$(dirname "$path")"
			printf 'changed\n' >"$path"
		done
		git add .
		git commit -qm 'change classified paths'
		detect_changes "$base" "$(git rev-parse HEAD)"
		[ "$status" -eq 0 ]
		assert_categories $categories
	done <<'EOF'
chezmoi windows|chezmoi/config.tmpl
nix darwin|nix/modules/aerospace/default.nix
nix wsl|nix/modules/1password/op-ssh-sign-wsl
nix wsl|nix/modules/editors/vscode.nix
nix linux darwin wsl|nix/modules/1password/default.nix
nix wsl chezmoi windows|nix/modules/fonts/wsl-fontconfig.conf
nix linux darwin wsl chezmoi windows|nix/defaults.nix
nix linux darwin wsl chezmoi windows|nix/home/keybindings/bindings.nix
nix linux darwin wsl chezmoi windows|nix/home/keybindings/generated.json
nix linux darwin wsl chezmoi windows|nix/modules/terminals/ghostty/ghostty.nix
nix linux darwin wsl chezmoi windows|nix/modules/terminals/ghostty/ghostty-renderer.nix
nix linux darwin wsl chezmoi windows|nix/modules/terminals/ghostty/ghostty-wsl.nix
nix linux darwin wsl chezmoi windows|nix/modules/editors/nvim/neovim.nix
nix linux|nix/modules/hyprland/hyprland-renderer.nix
nix chezmoi windows|windows/winget/packages.json
nix chezmoi other linux darwin wsl windows|scripts/sh/install-macos.sh
nix chezmoi other linux darwin wsl windows|.github/workflows/ci-chezmoi.yml
nix chezmoi other linux darwin wsl windows|taskfiles/hermes/taskfile.yml
|README.md;docs/architecture.md;nix/hosts/AGENTS.md
chezmoi windows|chezmoi/prompt.md
chezmoi windows|chezmoi/dot_codex/AGENTS.md
nix linux darwin wsl|nix/modules/shells/bash/bashrc
other|config/other.json
nix linux darwin wsl chezmoi windows|nix/odd\n name.nix;chezmoi/config.tmpl
EOF
}

@test "change detector run-all enables every category without a Git diff" {
	git_fixture "$BATS_TEST_TMPDIR/repository"
	detect_changes unused-base unused-head true
	[ "$status" -eq 0 ]
	assert_categories nix chezmoi other linux darwin wsl windows
	[ ! -e "$RUNNER_TEMP/ci-changed-paths" ]
}

@test "deleted renamed and type-changed paths retain their category" {
	for change in delete rename type; do
		git_fixture "$BATS_TEST_TMPDIR/$change"
		commit_nix
		base=$(git rev-parse HEAD)
		if [[ $change == rename ]]; then
			git mv nix/example.nix renamed-installer.sh
		else
			rm nix/example.nix
			if [[ $change == type ]]; then ln -s ../target nix/example.nix; fi
		fi
		git add -A
		git commit -qm "$change"
		detect_changes "$base" "$(git rev-parse HEAD)"
		[ "$status" -eq 0 ]
		grep -Fxq nix=true "$GITHUB_OUTPUT"
		{
			printf 'nix/example.nix\0'
			if [[ $change == rename ]]; then printf 'renamed-installer.sh\0'; fi
		} >"$BATS_TEST_TMPDIR/expected"
		cmp "$RUNNER_TEMP/ci-changed-paths" "$BATS_TEST_TMPDIR/expected"
	done
}

@test "pull-request detection ignores changes made only on the base branch" {
	git_fixture "$BATS_TEST_TMPDIR/repository"
	git branch pull-request
	mkdir chezmoi
	printf 'base change\n' >chezmoi/base.tmpl
	git add .
	git commit -qm 'advance base'
	base=$(git rev-parse HEAD)
	git switch pull-request
	commit_nix
	detect_changes "$base" "$(git rev-parse HEAD)" false pull_request
	[ "$status" -eq 0 ]
	grep -Fxq nix=true "$GITHUB_OUTPUT"
	grep -Fxq chezmoi=false "$GITHUB_OUTPUT"
}
