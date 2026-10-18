#!/bin/bash
set -euo pipefail
export LC_ALL=C

fail() {
  printf '[macos-permissions] %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 2 ]] || fail 'Usage: ensure-macos-permissions.sh CALLER_HOME TOUCH_EXECUTABLE'
[[ $EUID -eq 0 ]] || fail 'Run this helper through sudo from the installing user.'
[[ $(/usr/bin/uname -s) == Darwin ]] || fail 'This helper requires macOS.'
[[ -n ${SUDO_USER:-} && ${SUDO_USER:-} != root && ${SUDO_UID:-} =~ ^[0-9]+$ ]] ||
  fail 'SUDO_USER and SUDO_UID must identify the installing user.'
caller_user=$SUDO_USER
caller_uid=$SUDO_UID
[[ $caller_uid -ne 0 && $(/usr/bin/id -u "$caller_user") == "$caller_uid" ]] ||
  fail 'SUDO_USER and SUDO_UID do not identify the same non-root user.'
caller_home=$1
touch_command=$2
[[ $caller_home == /* && -d $caller_home ]] || fail 'CALLER_HOME must be an existing absolute directory.'
[[ $touch_command == /* && -f $touch_command && -x $touch_command ]] ||
  fail 'TOUCH_EXECUTABLE must be an absolute executable path.'

failed_path=''
probe_error=''
show_failure() {
  printf '[macos-permissions] %s check failed: %s\n%s\n' "$access_description" "$failed_path" "$probe_error" >&2
  printf 'Open System Settings > Privacy & Security > %s.\n' "$permission_name" >&2
  printf '%s\n' \
    'Enable the terminal running ./install.sh: Ghostty when using Ghostty, or Terminal when using Terminal.' \
    'If macOS requests a relaunch after granting access, quit and reopen that terminal and rerun ./install.sh.' >&2
}

probe_failure() {
  case "$probe_error" in
  sudo:*)
    show_failure
    fail 'Cannot run the user access check; resolve the sudo error and rerun ./install.sh.'
    ;;
  *'Operation not permitted'* | *'Permission denied'*) return 1 ;;
  *)
    show_failure
    fail 'Resolve the access error above and rerun ./install.sh.'
    ;;
  esac
}

check_recent_documents() {
  # Homebrew zap uses Dir.glob here to find the removed app's recent-document list.
  # Check that actual metadata access, rather than inferring a global FDA state.
  failed_path="$caller_home/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"
  if probe_error=$(/usr/bin/sudo -n --user "$caller_user" --set-home \
    /bin/ls -A "$failed_path" 2>&1 >/dev/null); then
    return 0
  fi
  case "$probe_error" in
  sudo:*) probe_failure ;;
  "ls: $failed_path: No such file or directory") return 0 ;;
  *) probe_failure ;;
  esac
}

probe_app() {
  local bundle=$1 context=$2
  if [[ $context == user ]]; then
    # Home Manager's copyApps activation checks with the native touch command.
    if probe_error=$(/usr/bin/sudo -n --user "$caller_user" --set-home \
      /usr/bin/touch "$bundle/.DS_Store" 2>&1); then
      return 0
    fi
  elif probe_error=$("$touch_command" "$bundle/.DS_Store" 2>&1); then
    return 0
  fi
  failed_path=$bundle
  probe_failure
}

check_apps() {
  local bundle
  # nix-darwin removes these optional Apple bundles during postActivation.
  # Probe each present cleanup target even on a first install, when the Nix app
  # directories may still be empty.
  for bundle in \
    /Applications/GarageBand.app \
    /Applications/iMovie.app \
    /Applications/Pages.app \
    /Applications/Numbers.app \
    /Applications/Keynote.app; do
    [[ -d $bundle ]] || continue
    probe_app "$bundle" root || return 1
  done
  for bundle in /Applications/Nix\ Apps/*.app; do
    [[ -d $bundle ]] || continue
    probe_app "$bundle" root || return 1
  done
  for bundle in "$caller_home"/Applications/Home\ Manager\ Apps/*.app; do
    [[ -d $bundle ]] || continue
    probe_app "$bundle" user || return 1
  done
  return 0
}

ensure_access() {
  permission_name=$1
  access_description=$2
  local anchor=$3 check_function=$4 wait_until
  if "$check_function"; then
    return 0
  fi
  show_failure
  [[ -t 0 && -t 2 ]] || fail 'Permission is unavailable in this noninteractive session; grant access and rerun ./install.sh.'
  if [[ $(/bin/launchctl managername) != Aqua ]] ||
    ! /bin/launchctl print "gui/$caller_uid" >/dev/null 2>&1; then
    fail 'Run ./install.sh from the installing user terminal in a graphical macOS session.'
  fi

  if ! /bin/launchctl asuser "$caller_uid" /usr/bin/sudo -n --user "$caller_user" --set-home \
    /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?$anchor"; then
    fail "Could not open $permission_name; open the settings above, grant access, and rerun ./install.sh."
  fi
  printf '[macos-permissions] Waiting up to 120 seconds for %s access...\n' "$permission_name" >&2
  wait_until=$((SECONDS + 120))
  while ((SECONDS + 2 <= wait_until)); do
    /bin/sleep 2
    ((SECONDS < wait_until)) || break
    if "$check_function"; then
      ((SECONDS <= wait_until)) || break
      printf '[macos-permissions] %s check passed; continuing installation.\n' "$access_description" >&2
      return 0
    fi
  done
  show_failure
  fail "Timed out waiting for $permission_name access; grant access and rerun ./install.sh."
}

ensure_access 'Full Disk Access' 'Homebrew recent-document metadata access' Privacy_AllFiles check_recent_documents
ensure_access 'App Management' 'System and user app write' Privacy_AppBundles check_apps
