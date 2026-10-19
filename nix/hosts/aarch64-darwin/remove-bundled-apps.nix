{ pkgs }:
let
  inherit (pkgs) lib;
  allowedApps = [
    {
      name = "GarageBand.app";
      bundleIdentifiers = [ "com.apple.garageband10" ];
    }
    {
      name = "iMovie.app";
      bundleIdentifiers = [ "com.apple.iMovieApp" ];
    }
    {
      name = "Pages.app";
      bundleIdentifiers = [
        "com.apple.iWork.Pages"
        "com.apple.Pages"
      ];
    }
    {
      name = "Numbers.app";
      bundleIdentifiers = [
        "com.apple.iWork.Numbers"
        "com.apple.Numbers"
      ];
    }
    {
      name = "Keynote.app";
      bundleIdentifiers = [
        "com.apple.iWork.Keynote"
        "com.apple.Keynote"
      ];
    }
  ];
in
pkgs.writeShellApplication {
  name = "remove-bundled-apple-apps";
  text = ''
    fail() {
      printf 'Apple app cleanup: %s\n' "$*" >&2
      exit 1
    }

    if [[ "$#" -ne 1 || -z "$1" ]]; then
      fail 'expected one Applications directory argument'
    fi
    applications_directory="$1"
    [[ -d "$applications_directory" && ! -L "$applications_directory" ]] \
      || fail "Applications path is not a normal directory: $applications_directory"
    selected_apps=()

    validate_app() {
      local app_path="$applications_directory/$1"
      shift
      [[ ! -L "$app_path" ]] || fail "selected app is a symlink: $app_path"
      [[ -e "$app_path" ]] || return 0
      [[ -d "$app_path" ]] || fail "selected app is not a directory: $app_path"

      local plist="$app_path/Contents/Info.plist"
      [[ -f "$plist" && -r "$plist" ]] || fail "Info.plist is missing or unreadable: $plist"
      local identifier expected
      if ! identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)"; then
        fail "cannot read CFBundleIdentifier: $plist"
      fi
      for expected in "$@"; do
        if [[ "$identifier" == "$expected" ]]; then
          selected_apps+=("$app_path")
          return 0
        fi
      done
      fail "unexpected bundle identifier '$identifier': $app_path"
    }

    # Validate every present selection before removing any bundle.
    ${lib.concatMapStringsSep "\n" (
      app: "validate_app ${lib.escapeShellArgs ([ app.name ] ++ app.bundleIdentifiers)}"
    ) allowedApps}

    for app_path in "''${selected_apps[@]}"; do
      printf 'Removing optional Apple app: %s\n' "$app_path"
      ${pkgs.coreutils}/bin/rm -rf -- "$app_path"
    done
  '';
}
