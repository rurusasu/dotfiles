#!/usr/bin/env bash
set -euo pipefail

sandbox=false
if [[ ${1:-} == --sandbox && $# -eq 1 ]]; then
  sandbox=true
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--sandbox]" >&2
  exit 64
fi

for tool in bash git jq nix node python3 statix tar task xz; do
  if ! command -v "$tool" >/dev/null; then
    echo "Missing bootstrap CI tool: $tool" >&2
    exit 1
  fi
done

bash -lc 'command -v git >/dev/null && command -v nix >/dev/null'

node -e 'if (Number(process.versions.node.split(".")[0]) < 24) process.exit(1)'
nix eval --json --expr '1 + 1' | grep -qx 2
nix store info --store local
nix config show --json | jq -e '
  .http2.value == false
  and .["stalled-download-timeout"].value == 60
  and .["download-attempts"].value == 3
  and (.substituters.value | index("https://cache.nixos.org?priority=10") != null)
' >/dev/null

fixture=$(mktemp -d)
trap 'rm -r "$fixture"' EXIT
printf '{ value = 1; }\n' >"$fixture/default.nix"
statix check "$fixture"
printf 'true == true\n' >"$fixture/default.nix"
if statix check "$fixture" >"$fixture/statix.log" 2>&1; then
  echo "statix did not reject the invalid fixture" >&2
  exit 1
fi

if [[ $sandbox == true ]]; then
  CI_BASH=$(readlink -f "$(command -v bash)")
  export CI_BASH
  # Nix expands $out inside the builder shell.
  # shellcheck disable=SC2016
  nix build --impure --no-link --expr 'derivation {
    name = "bootstrap-ci-sandbox";
    system = "x86_64-linux";
    builder = builtins.storePath (builtins.getEnv "CI_BASH");
    args = [ "-c" "echo sandbox-ok > $out" ];
  }'
fi

echo "Bootstrap CI tools verified."
