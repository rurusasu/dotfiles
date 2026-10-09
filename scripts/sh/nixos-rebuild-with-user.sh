#!/usr/bin/env bash
set -euo pipefail

# nixos-rebuild evaluates the flake as root. Pass the invoking user's identity
# through sudo so Home Manager keeps targeting the same account on every
# rebuild, not only during the initial WSL postinstall.
user="${DOTFILES_USER:-${SUDO_USER:-${USER:-}}}"
[[ -n $user ]] || {
  echo "Unable to determine the NixOS user." >&2
  exit 1
}

home="${DOTFILES_HOME:-}"
if [[ -z $home ]]; then
  if command -v getent >/dev/null 2>&1; then
    home="$(getent passwd "$user" | cut -d: -f6)"
  else
    home="/home/$user"
  fi
fi
[[ $home == /* ]] || {
  echo "Unable to determine an absolute home directory for $user." >&2
  exit 1
}

uid="${DOTFILES_UID:-$(id -u "$user")}"
gid="${DOTFILES_GID:-$(id -g "$user")}"
group="${DOTFILES_GROUP:-$(id -gn "$user")}"

# Derive the declaration from this invocation, not an inherited trust value.
# Keep the public rebuild arguments unchanged, including path: and #selectors.
flake_ref=""
flake_seen=0
expect_flake=0
for argument in "$@"; do
  if [[ $expect_flake == 1 ]]; then
    flake_ref="$argument"
    expect_flake=0
  elif [[ $argument == --flake || $argument == --flake=* ]]; then
    [[ $flake_seen == 0 ]] || {
      echo "Multiple --flake references are ambiguous." >&2
      exit 1
    }
    flake_seen=1
    if [[ $argument == --flake ]]; then
      expect_flake=1
    else
      flake_ref="${argument#--flake=}"
    fi
  fi
done
[[ $expect_flake == 0 && ($flake_seen == 0 || -n $flake_ref) ]] || {
  echo "--flake requires a reference." >&2
  exit 1
}
flake_directory="${flake_ref%%#*}"
repository=""
case "$flake_directory" in
path:*) flake_directory="${flake_directory#path:}" ;;
*:*) flake_directory="" ;; # Remote/provider references are not local trust inputs.
esac
if [[ -n $flake_directory && -d $flake_directory ]]; then
  repository="$(cd "$flake_directory" && pwd -P)"
  [[ $repository != *'*'* ]] || {
    echo "Checkout trust cannot contain wildcards." >&2
    exit 1
  }
fi

state_dir="${DOTFILES_STATE_DIR:-/var/lib/dotfiles}"
state_version_file="$state_dir/system-state-version"
if [[ -n ${DOTFILES_STATE_VERSION:-} ]]; then
  state_version="$DOTFILES_STATE_VERSION"
elif [[ -r $state_version_file ]]; then
  state_version="$(cat "$state_version_file")"
elif [[ -e /run/current-system ]]; then
  # Existing systems keep their original state schema unless migration is
  # explicitly requested. Fresh installers pass an explicit state version.
  state_version="25.05"
else
  state_version="26.05"
fi
[[ $state_version =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  echo "Invalid DOTFILES_STATE_VERSION: $state_version (expected YY.MM)." >&2
  exit 1
}

rebuild_env=(
  "DOTFILES_USER=$user"
  "DOTFILES_HOME=$home"
  "DOTFILES_UID=$uid"
  "DOTFILES_GID=$gid"
  "DOTFILES_GROUP=$group"
  "DOTFILES_REPO_ROOT=$repository"
  "DOTFILES_STATE_VERSION=$state_version"
)

accept_flake_config="${DOTFILES_ACCEPT_FLAKE_CONFIG:-0}"
case "$accept_flake_config" in
0) ;;
1)
  nix_config="${NIX_CONFIG:-}"
  case "$nix_config" in
  *$'accept-flake-config = true'*) ;;
  *)
    [[ -z $nix_config ]] || nix_config+=$'\n'
    nix_config+="accept-flake-config = true"
    ;;
  esac
  rebuild_env+=("NIX_CONFIG=$nix_config")
  ;;
*)
  echo "Invalid DOTFILES_ACCEPT_FLAKE_CONFIG: $accept_flake_config (expected 0 or 1)." >&2
  exit 1
  ;;
esac

if [[ $(id -u) -eq 0 ]]; then
  /usr/bin/env "${rebuild_env[@]}" nixos-rebuild "$@"
  rebuild_status=$?
else
  sudo /usr/bin/env "${rebuild_env[@]}" nixos-rebuild "$@"
  rebuild_status=$?
fi

if [[ $rebuild_status -eq 0 && ${1:-} == "switch" ]]; then
  if [[ $(id -u) -eq 0 ]]; then
    install -d -m 0755 "$state_dir"
    printf '%s\n' "$state_version" >"$state_version_file"
    chmod 0644 "$state_version_file"
  else
    sudo install -d -m 0755 "$state_dir"
    printf '%s\n' "$state_version" | sudo tee "$state_version_file" >/dev/null
  fi
fi

exit "$rebuild_status"
