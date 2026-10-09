#!/usr/bin/env bash
set -euo pipefail
umask 077

destination="$1"
account="$2"
reference="$3"
read_timeout_seconds="$4"

op_command=(op)
if [[ -n ${WSL_DISTRO_NAME:-} ]] && command -v op.exe >/dev/null 2>&1; then
  op_command=(op.exe --cache=false)
fi

# Do not log field contents or CLI output. A locked/unavailable account must
# not remove an existing key or block the rest of Home Manager activation.
if public_key="$(timeout --kill-after=5s "${read_timeout_seconds}s" "${op_command[@]}" read "$reference" --account "$account" </dev/null 2>/dev/null)"; then
  public_key="${public_key//$'\r'/}"
else
  status=$?
  printf 'WARNING: 1Password SSH public key read failed (exit %s); existing key preserved. Sign in/unlock 1Password and rerun Home Manager activation.\n' "$status" >&2
  exit 0
fi

# Accept a single OpenSSH public-key line, not private keys or multiline data.
if [[ $public_key == *$'\n'* ]] || [[ $public_key != ssh-* && $public_key != ecdsa-* && $public_key != sk-* ]]; then
  printf 'WARNING: 1Password returned an invalid SSH public key; existing key preserved.\n' >&2
  exit 0
fi

ssh_directory="$(dirname "$destination")"
install -d -m 0700 "$ssh_directory"
temporary_key="$(mktemp "$ssh_directory/.signing_key.pub.XXXXXX")"
trap 'rm -f -- "$temporary_key"' EXIT
printf '%s\n' "$public_key" >"$temporary_key"
if ! ssh-keygen -l -f "$temporary_key" >/dev/null 2>&1; then
  printf 'WARNING: 1Password returned an invalid SSH public key; existing key preserved.\n' >&2
  exit 0
fi

chmod 0644 "$temporary_key"
mv -fT -- "$temporary_key" "$destination"
