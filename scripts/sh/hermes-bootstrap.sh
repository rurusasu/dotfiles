#!/usr/bin/env bash

set -euo pipefail

if [[ $- == *x* ]]; then
  set +x
fi

hermes_home="${HERMES_HOME:-${HOME:?HOME is not set}/.hermes}"
manifest="${HERMES_BOOTSTRAP_MANIFEST:-$hermes_home/bootstrap-manifest.yaml}"
bootstrap_bin="${DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE:-hermes-bootstrap}"
op_bin="${DOTFILES_HERMES_OP_EXECUTABLE:-op}"
op_account="${DOTFILES_HERMES_OP_SERVICE_ACCOUNT_ACCOUNT:-my.1password.com}"
op_reference="${DOTFILES_HERMES_OP_SERVICE_ACCOUNT_TOKEN_REF:-op://openclaw/3bgd5qtytxuvuauauyqr2p4iki/credential}"

fail() {
  printf 'Hermes native bootstrap: %s\n' "$1" >&2
  exit 1
}

command -v "$bootstrap_bin" >/dev/null 2>&1 || fail "Nix-managed Hermes bootstrap command is unavailable."
command -v "$op_bin" >/dev/null 2>&1 || fail "1Password CLI (op) is required."
command -v jq >/dev/null 2>&1 || fail "jq is required."
[[ -f $manifest ]] || fail "Nix-managed bootstrap manifest is missing."

account_token=""
if ! account_token="$($op_bin --account "$op_account" read "$op_reference" 2>/dev/null)" ||
  [[ -z $account_token || $account_token == *$'\n'* || $account_token == *$'\r'* ]]; then
  unset account_token
  fail "Hermes 1Password Service Account could not be loaded."
fi

secret_plan=""
if ! secret_plan="$($bootstrap_bin secret-plan --manifest "$manifest" 2>/dev/null)"; then
  unset account_token
  fail "Hermes native bootstrap secret plan could not be generated."
fi

emit_payload() {
  local item_plan key account vault item record
  printf '%s\n' '{"type":"header","schema_version":1}' || return 141
  while IFS= read -r item_plan; do
    key="$(jq -r '.key' <<<"$item_plan")"
    account="$(jq -r '.account' <<<"$item_plan")"
    vault="$(jq -r '.vault' <<<"$item_plan")"
    item="$(jq -r '.item' <<<"$item_plan")"
    if ! record="$(OP_SERVICE_ACCOUNT_TOKEN="$account_token" \
      "$op_bin" --account "$account" item get "$item" --vault "$vault" --format json 2>/dev/null |
      jq -ce --arg key "$key" 'if type == "object" then {type: "item", key: $key, item: .} else error("invalid item") end' 2>/dev/null)"; then
      return 1
    fi
    printf '%s\n' "$record" || return 141
    unset record item_plan
  done < <(jq -c '.items[]' <<<"$secret_plan")
  printf '%s\n' '{"type":"end"}'
}

set -o pipefail
if emit_payload | "$bootstrap_bin" apply --manifest "$manifest"; then
  unset account_token secret_plan
else
  statuses=("${PIPESTATUS[@]}")
  producer_status="${statuses[0]:-1}"
  bootstrap_status="${statuses[1]:-1}"
  unset account_token secret_plan
  if ((producer_status == 141 && bootstrap_status != 0)); then
    exit "$bootstrap_status"
  fi
  if ((producer_status != 0)); then
    fail "Hermes secret payload could not be read from 1Password."
  fi
  exit "$bootstrap_status"
fi
