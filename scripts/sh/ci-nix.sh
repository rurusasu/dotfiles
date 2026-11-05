#!/usr/bin/env bash
# Nix platform operations; phase ordering belongs to taskfiles/ci/taskfile.yml.
set -euo pipefail
phase=${1:?phase is required}
target=${2:?target is required}
: "${CI_STATE:?absolute CI state directory is required}"
: "${TESTED_SHA:?tested source SHA is required}"
[[ $CI_STATE == /* && $TESTED_SHA =~ ^[0-9a-f]{40}$ ]] || exit 64
case $target in linux | darwin) ;; *) exit 64 ;; esac
mkdir -p "$CI_STATE"
repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)

case $phase in
source | checks | build)
  # Retry individual read/build operations, never the state-changing installer.
  nix() { bash "$repository/scripts/sh/retry-ci-dns.sh" nix "$@"; }
  ;;
esac

source_path() { jq -er .path "$CI_STATE/source.json"; }
root_path() { jq -er --arg name "$1" '.[$name]' "$CI_STATE/artifacts/$target/roots.json"; }
record_root() {
  local file="$CI_STATE/roots-$1.json"
  [[ -f $file ]] || printf '{}\n' >"$file"
  jq --arg name "$2" --arg path "$3" '. + {($name): $path}' "$file" >"$file.tmp"
  mv "$file.tmp" "$file"
}

wait_for_hermes() {
  local curl jq deadline response
  curl="$(root_path curl)/bin/curl"
  jq="$(root_path jq)/bin/jq"
  deadline=$((SECONDS + 300))
  while :; do
    # shellcheck disable=SC2016 # jq variables must not be expanded by Bash.
    if response=$("$curl" --fail --silent --show-error --max-time 2 \
      -H 'Authorization: Bearer dotfiles-ci-health-probe' http://127.0.0.1:18642/health/detailed 2>&1) &&
      printf '%s' "$response" | "$jq" -e '
        .status == "ok" and .readiness.status == "ok" and
        (.readiness.checks | type == "object" and all(.[]; .status == "ok")) and
        (.readiness.checks as $checks | all(
          ["state_db", "session_store", "config", "model", "disk", "gateway", "background_queues"][];
          . as $required | $checks[$required].status == "ok"))
      ' >/dev/null; then break; fi
    if ((SECONDS >= deadline)); then
      printf '%s\n' "$response" >&2
      return 1
    fi
    sleep 1
  done
  [[ $("$curl" --silent --show-error --max-time 2 --output /dev/null --write-out '%{http_code}' http://127.0.0.1:18642/health/detailed) == 401 ]]
  [[ $("$curl" --silent --show-error --max-time 2 --output /dev/null --write-out '%{http_code}' -H 'Authorization: Bearer invalid-ci-key' http://127.0.0.1:18642/health/detailed) == 401 ]]
}

case $phase in
source)
  [[ $(git -C "$repository" rev-parse HEAD) == "$TESTED_SHA" ]]
  git -C "$repository" diff --exit-code --quiet
  git -C "$repository" diff --cached --exit-code --quiet
  cd "$repository"
  nix flake archive --json --no-write-lock-file . >"$CI_STATE/source.json"
  frozen=$(source_path)
  # shellcheck disable=SC2016 # This interpolation is Nix syntax.
  CI_SOURCE_ROOT="$frozen" nix eval --impure --json --expr '
    let f = builtins.getFlake (builtins.getEnv "CI_SOURCE_ROOT");
        p = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
    in builtins.mapAttrs (_: pkg: { path = pkg.outPath; drv = pkg.drvPath; })
      { python = p.python3; curl = p.curl; jq = p.jq; zstd = p.zstd.bin; }
  ' >"$CI_STATE/tools.json"
  tools=()
  while IFS= read -r drv; do tools+=("$drv^*"); done < <(jq -er '.[].drv' "$CI_STATE/tools.json")
  nix build --out-link "$CI_STATE/tool" "${tools[@]}"
  jq -er .python.path "$CI_STATE/tools.json" >"$CI_STATE/python-path"
  ;;
checks)
  source=$(source_path)
  system=$(nix eval --impure --raw --expr builtins.currentSystem)
  # VM drivers are built here; VM execution belongs to the E2E consumer.
  selection='builtins.attrValues checks'
  if [[ $target == linux && ${CI_LINUX_REQUIRED:-false} != true ]]; then
    selection='builtins.filter (check: !(check ? driver)) (builtins.attrValues checks)'
  fi
  nix eval --json "$source#checks.$system" --apply \
    "checks: map (check: (check.driver or check).drvPath) ($selection)" >"$CI_STATE/checks.json"
  [[ $(jq length "$CI_STATE/checks.json") -gt 0 ]]
  checks=()
  while IFS= read -r check; do checks+=("$check^*"); done < <(jq -er '.[]' "$CI_STATE/checks.json")
  nix build --no-link --no-write-lock-file --print-build-logs "${checks[@]}"
  ;;
build)
  source=$(source_path)
  if [[ $target == darwin ]]; then
    # shellcheck source=/dev/null
    source "$repository/scripts/sh/lib/darwin-flake.sh"
    write_darwin_flake "$CI_STATE/darwin-flake" "$(id -un)" true
    nix flake lock --offline --override-input dotfiles "$source" "path:$CI_STATE/darwin-flake"
    nix flake archive --json "path:$CI_STATE/darwin-flake" >"$CI_STATE/deployment.json"
    deployment=$(jq -er .path "$CI_STATE/deployment.json")
    system=$(nix build --no-link --print-out-paths --print-build-logs "$deployment#darwinConfigurations.macos.system")
    record_root darwin system "$system"
    record_root darwin deployment "$deployment"
    program=$(nix eval --raw "$source#apps.aarch64-darwin.darwin-rebuild.program")
    rebuild=${program%/bin/*}
    nix-store --realise "$rebuild"
    record_root darwin rebuild "$rebuild"
  else
    if [[ ${CI_LINUX_REQUIRED:-false} == true ]]; then
      install -D -m 0644 "$source/nix/tests/fixtures/hardware-configuration.nix" /etc/nixos/hardware-configuration.nix
      nix build --impure --no-link --print-build-logs \
        "$source#nixosConfigurations.linux.config.system.build.toplevel" \
        "$source#homeConfigurations.x86_64-linux.activationPackage"
      driver=$(nix build --no-link --print-out-paths "$source#checks.x86_64-linux.native-linux-vm.driver")
      record_root linux driver "$driver"
    fi
    if [[ ${CI_WSL_REQUIRED:-false} == true ]]; then
      system=$(nix build --impure --no-link --print-out-paths --print-build-logs "$source#nixosConfigurations.nixos.config.system.build.toplevel")
      record_root wsl system "$system"
    fi
  fi
  ;;
export)
  source=$(source_path)
  python=$(cat "$CI_STATE/python-path")
  targets=()
  if [[ $target == darwin ]]; then targets=(darwin); else
    [[ ${CI_LINUX_REQUIRED:-false} != true ]] || targets+=(linux)
    [[ ${CI_WSL_REQUIRED:-false} != true ]] || targets+=(wsl)
  fi
  for output in "${targets[@]}"; do
    arguments=(--root "source=$source")
    while IFS=$'\t' read -r name path; do arguments+=(--root "$name=$path"); done \
      < <(jq -r 'to_entries[] | [.key,.value.path] | @tsv' "$CI_STATE/tools.json")
    index=0
    while IFS= read -r input; do
      arguments+=(--root "input-$index=$input")
      index=$((index + 1))
    done < <(jq -r '[.. | objects | .path? // empty] | unique[]' "$CI_STATE/source.json")
    while IFS=$'\t' read -r name path; do arguments+=(--root "$name=$path"); done \
      < <(jq -r 'to_entries[] | [.key,.value] | @tsv' "$CI_STATE/roots-$output.json")
    PATH="$(jq -er .zstd.path "$CI_STATE/tools.json")/bin:$PATH" \
      "$python/bin/python3" -B "$repository/scripts/python/prepare_ci_nix_artifact.py" export \
      --target "$output" --tested-sha "$TESTED_SHA" --source "$source" \
      --output "$CI_STATE/artifacts/$output" "${arguments[@]}"
    printf '%s\n' "$python" >"$CI_STATE/artifacts/$output/bootstrap-python-path.txt"
  done
  ;;
import)
  artifact="$CI_STATE/artifacts/$target"
  python=$(cat "$artifact/bootstrap-python-path.txt")
  [[ $python =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9+._?=-]+$ ]] || exit 1
  nix-store --realise --option max-jobs 0 --option builders '' "$python"
  "$python/bin/python3" -B "$repository/scripts/python/prepare_ci_nix_artifact.py" import \
    --target "$target" --tested-sha "$TESTED_SHA" --input "$artifact"
  ;;
apply | run-vm)
  if [[ $target == linux ]]; then
    [[ $phase == run-vm ]] || exit 64
    # The driver exercises installer -> reboot -> assertions in its guest.
    driver=$(root_path driver)
    "$driver/bin/nixos-test-driver" >"$CI_STATE/linux-e2e.log" 2>&1 || {
      cat "$CI_STATE/linux-e2e.log"
      exit 1
    }
  else
    [[ $phase == apply ]] || exit 64
    source=$(root_path source)
    deployment=$(root_path deployment)
    [[ ${GITHUB_ACTIONS:-false} == true ]] || {
      echo 'macOS E2E requires a disposable runner.' >&2
      exit 1
    }
    launchctl print "gui/$(id -u)" >/dev/null
    mkdir -p "$HOME/.hermes/memories"
    printf '%s\n' 'OPENROUTER_API_KEY=ci' 'API_SERVER_ENABLED=true' 'API_SERVER_KEY=dotfiles-ci-health-probe' 'API_SERVER_PORT=18642' >"$HOME/.hermes/.env"
    printf '%s\n' 'model:' '  default: openrouter/auto' >"$HOME/.hermes/config.yaml"
    printf '%s\n' preserve-existing-hermes-state >"$HOME/.hermes/memories/dotfiles-ci-state-preservation.txt"
    chmod 600 "$HOME/.hermes/.env" "$HOME/.hermes/config.yaml" "$HOME/.hermes/memories/dotfiles-ci-state-preservation.txt"
    UPDATE_FLAKE_INPUTS=false DOTFILES_ALLOW_BUILDS=false \
      DOTFILES_FLAKE_REF="$deployment#macos" "$source/install.sh"
    [[ $(cd /nix/var/nix/profiles/system && pwd -P) == "$(root_path system)" ]]
    # Prove activation auto-starts the service before explicitly restarting it.
    wait_for_hermes
  fi
  ;;
restart)
  [[ $target == darwin ]] || exit 64
  launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.hermes-agent"
  ;;
verify)
  [[ $target == darwin ]] || exit 64
  system=$(root_path system)
  [[ $(cd /nix/var/nix/profiles/system && pwd -P) == "$system" ]]
  /bin/zsh -lic 'command -v hermes && hermes --version && codex --version && command -v nvim'
  launchctl print "gui/$(id -u)/org.nix-community.home.hermes-agent" >"$CI_STATE/hermes-launchd.txt"
  grep -Eq 'state = running|pid = [0-9]+' "$CI_STATE/hermes-launchd.txt"
  wait_for_hermes
  grep -qx preserve-existing-hermes-state "$HOME/.hermes/memories/dotfiles-ci-state-preservation.txt"
  [[ $(stat -f %Lp "$HOME/.hermes/.env") == 600 ]]
  grep -qx OPENROUTER_API_KEY=ci "$HOME/.hermes/.env"
  grep -qx API_SERVER_PORT=18642 "$HOME/.hermes/.env"
  brew list --cask --versions >"$CI_STATE/homebrew-casks.txt"
  for cask in docker-desktop steam; do grep -Eq "^$cask " "$CI_STATE/homebrew-casks.txt"; done
  ;;
*) exit 64 ;;
esac
