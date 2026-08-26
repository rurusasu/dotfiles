#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TART_COMMAND="${DOTFILES_TART_COMMAND:-tart}"
SSH_COMMAND="${DOTFILES_TART_SSH_COMMAND:-ssh}"
VM_NAME="${DOTFILES_TART_VM_NAME:-tahoe-base}"
VM_USER="${DOTFILES_TART_VM_USER:-admin}"
HINDSIGHT_PORT="${HINDSIGHT_API_PORT:-8888}"
WAIT_ATTEMPTS="${DOTFILES_TART_IP_WAIT_ATTEMPTS:-60}"
WAIT_DELAY="${DOTFILES_TART_IP_WAIT_DELAY_SECONDS:-2}"
STATE_DIR="${DOTFILES_TART_RUN_STATE_DIR:-$HOME/.local/state/dotfiles/tart}"
CONTROL_SOCKET="$STATE_DIR/${VM_NAME}.ssh"
KNOWN_HOSTS="$STATE_DIR/known_hosts"
tart_pid=""
tunnel_open=0

die() {
  printf 'tart-run: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if ((tunnel_open == 1)); then
    "$SSH_COMMAND" -S "$CONTROL_SOCKET" -O exit "$VM_USER@$vm_ip" >/dev/null 2>&1 || true
  fi
  [[ -z $tart_pid ]] || kill "$tart_pid" >/dev/null 2>&1 || true
  rm -f -- "$CONTROL_SOCKET"
}

wait_for_ip() {
  local attempt ip
  for ((attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++)); do
    ip="$($TART_COMMAND ip "$VM_NAME" 2>/dev/null || true)"
    if [[ -n $ip ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
    kill -0 "$tart_pid" >/dev/null 2>&1 || die "Tart exited before the VM obtained an IP address."
    ((attempt == WAIT_ATTEMPTS)) || sleep "$WAIT_DELAY"
  done
  die "VM did not obtain an IP address after $WAIT_ATTEMPTS attempts."
}

for command in "$TART_COMMAND" "$SSH_COMMAND"; do
  [[ $command == */* ]] || command -v "$command" >/dev/null 2>&1 || die "$command is required."
done
[[ $VM_NAME =~ ^[A-Za-z0-9._-]+$ && $VM_NAME != . && $VM_NAME != .. ]] ||
  die "DOTFILES_TART_VM_NAME contains unsupported characters: $VM_NAME"
[[ $HINDSIGHT_PORT =~ ^[0-9]+$ ]] && ((HINDSIGHT_PORT >= 1 && HINDSIGHT_PORT <= 65535)) ||
  die "HINDSIGHT_API_PORT must be between 1 and 65535."
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
trap cleanup EXIT INT TERM

"$TART_COMMAND" run "$VM_NAME" &
tart_pid=$!
vm_ip="$(wait_for_ip)"

ssh_options=(
  -o BatchMode=no
  -o ExitOnForwardFailure=yes
  -o StrictHostKeyChecking=accept-new
  -o "UserKnownHostsFile=$KNOWN_HOSTS"
)
"$SSH_COMMAND" "${ssh_options[@]}" -M -S "$CONTROL_SOCKET" -f -N \
  -R "127.0.0.1:8888:127.0.0.1:${HINDSIGHT_PORT}" \
  "$VM_USER@$vm_ip"
tunnel_open=1

"$SSH_COMMAND" "${ssh_options[@]}" -S "$CONTROL_SOCKET" "$VM_USER@$vm_ip" \
  'DOTFILES_RUNTIME=tart bash -s' <"$SCRIPT_DIR/sync-tart-dotfiles.sh"

printf 'tart-run: %s is running; Hindsight is available in the guest at 127.0.0.1:8888.\n' "$VM_NAME"
wait "$tart_pid"
