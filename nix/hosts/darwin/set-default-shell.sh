#!/usr/bin/env bash
set -euo pipefail

# nix-darwin runs this after building the system closure and registering shells.
# Its activation PATH contains only managed tools and macOS system directories.
user="${1:?A local user is required}"
shell="${2:?An installed shell is required}"

die() {
  printf 'default-shell: %s\n' "$*" >&2
  exit 1
}

[[ $(id -u) == 0 ]] || die "Activation must run as root."
uid="$(id -u "$user")" || die "Local user does not exist: $user"
[[ $uid =~ ^[0-9]+$ && $uid != 0 ]] || die "Refusing to change the root account."
[[ $shell == /* && -x $shell ]] || die "Shell is not installed or executable: $shell"
grep -Fxq -- "$shell" /etc/shells || die "Shell is not registered in /etc/shells: $shell"

read_shell() {
  local entry current
  entry="$(dscl . -read "/Users/$user" UserShell)" || return 1
  [[ $entry == 'UserShell: '* ]] || return 1
  current="${entry#UserShell: }"
  [[ $current == /* && $current != *$'\n'* ]] || return 1
  printf '%s\n' "$current"
}

current_shell="$(read_shell)" || die "Unable to read the local login shell for $user."
[[ $current_shell != "$shell" ]] || exit 0

# Match dscl's local directory node; do not modify a network-directory account.
chsh -l /Local/Default -s "$shell" "$user" || die "Unable to change the login shell for $user."

# chsh can report an Open Directory write error yet exit successfully.
current_shell="$(read_shell)" || die "Unable to verify the login shell for $user."
[[ $current_shell == "$shell" ]] || die "The login shell for $user did not change."
