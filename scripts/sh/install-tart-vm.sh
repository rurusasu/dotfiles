#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_ROOT="${DOTFILES_ROOT:-$ROOT}"
export DOTFILES_LOG_PREFIX="${DOTFILES_LOG_PREFIX:-tart-install}"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"

TART_COMMAND="${DOTFILES_TART_COMMAND:-tart}"
TART_IMAGE="${DOTFILES_TART_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
TART_VM_NAME="${DOTFILES_TART_VM_NAME:-tahoe-base}"
TART_HOME_ROOT="${TART_HOME:-$HOME/.tart}"
MIN_FREE_GIB="${DOTFILES_TART_MIN_FREE_GIB:-40}"

require_tart_command() {
	if [[ $TART_COMMAND == */* ]]; then
		[[ -x $TART_COMMAND ]] || dotfiles_die "Tart executable is unavailable: $TART_COMMAND"
	else
		dotfiles_have "$TART_COMMAND" || dotfiles_die "Tart is unavailable. Run the macOS installer first."
	fi
}

validate_configuration() {
	[[ $MIN_FREE_GIB =~ ^[0-9]+$ ]] ||
		dotfiles_die "DOTFILES_TART_MIN_FREE_GIB must be a non-negative integer: $MIN_FREE_GIB"
	[[ $TART_VM_NAME =~ ^[A-Za-z0-9._-]+$ ]] ||
		dotfiles_die "DOTFILES_TART_VM_NAME contains unsupported characters: $TART_VM_NAME"
	[[ $TART_VM_NAME != "." && $TART_VM_NAME != ".." ]] ||
		dotfiles_die "DOTFILES_TART_VM_NAME contains unsupported characters: $TART_VM_NAME"
	[[ -n $TART_IMAGE ]] || dotfiles_die "DOTFILES_TART_IMAGE must not be empty."
}

require_free_space() {
	local available_blocks required_blocks
	((MIN_FREE_GIB == 0)) && return 0

	available_blocks="$(df -Pk "$TART_HOME_ROOT" | awk 'NR == 2 { print $4 }')"
	[[ $available_blocks =~ ^[0-9]+$ ]] ||
		dotfiles_die "Unable to determine free space under TART_HOME: $TART_HOME_ROOT"
	required_blocks=$((MIN_FREE_GIB * 1024 * 1024))
	((available_blocks >= required_blocks)) ||
		dotfiles_die "Insufficient free space under TART_HOME: ${available_blocks} KiB available, ${MIN_FREE_GIB} GiB required."
}

main() {
	validate_configuration
	require_tart_command
	mkdir -p "$TART_HOME_ROOT"

	local vm_dir="$TART_HOME_ROOT/vms/$TART_VM_NAME"
	if [[ -e $vm_dir || -L $vm_dir ]]; then
		[[ -d $vm_dir ]] || dotfiles_die "Tart VM path is not a directory: $vm_dir"
		dotfiles_log "Tart VM already exists: $TART_VM_NAME"
		return 0
	fi
	require_free_space

	dotfiles_log "Cloning $TART_IMAGE as $TART_VM_NAME. The initial image download is large and may take a while..."
	TART_HOME="$TART_HOME_ROOT" "$TART_COMMAND" clone "$TART_IMAGE" "$TART_VM_NAME"
	[[ -d $vm_dir ]] || dotfiles_die "Tart clone completed without creating the VM: $vm_dir"
	dotfiles_log "Tart VM is ready: $TART_VM_NAME"
	dotfiles_log "Start it with: tart run $TART_VM_NAME"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	main "$@"
fi
