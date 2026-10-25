{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs) aerospace;
  openUrl = url: "/usr/bin/open ${lib.escapeShellArg url}";
  disabledShortcut = parameters: {
    enabled = false;
    value = {
      inherit parameters;
      type = "standard";
    };
  };
in
{
  programs.aerospace = {
    enable = true;
    package = aerospace;
    launchd.enable = true;
    settings = {
      config-version = 2;
      start-at-login = false;
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      accordion-padding = 30;
      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      key-mapping.preset = "qwerty";
      persistent-workspaces =
        map toString
          (import ../../home/keybindings/bindings.nix { inherit lib; }).workspaces;
      gaps = {
        inner.horizontal = 8;
        inner.vertical = 8;
        outer = {
          left = 8;
          right = 8;
          top = 8;
          bottom = 8;
        };
      };
      mode.main.binding =
        (import ./aerospace.nix {
          inherit lib;
          commands = (import ./darwin-commands.nix { inherit lib pkgs aerospace; }) // {
            capture = "/usr/bin/open -a Screenshot";
            lock = openUrl "raycast://extensions/raycast/system/lock-screen";
            audio = openUrl "x-apple.systempreferences:com.apple.Sound-Settings.extension";
            bluetooth = openUrl "x-apple.systempreferences:com.apple.BluetoothSettings";
            display = openUrl "x-apple.systempreferences:com.apple.Displays-Settings.extension";
            network = openUrl "x-apple.systempreferences:com.apple.wifi-settings-extension";
            power = openUrl "x-apple.systempreferences:com.apple.Battery-Settings.extension";
          };
        }).bindings;
      mode.passthrough.binding.cmd-ctrl-alt-esc = "mode main";
    };
  };

  # Pin the Home Manager-generated configuration even if a legacy dotfile exists.
  launchd.agents.aerospace.config = lib.mkIf config.programs.aerospace.enable {
    Program = lib.mkForce null;
    ProgramArguments = [
      "${aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"
      "--config-path"
      "${config.home.file.${
        if config.xdg.enable then
          "${lib.removePrefix config.home.homeDirectory config.xdg.configHome}/aerospace/aerospace.toml"
        else
          ".aerospace.toml"
      }.source
      }"
    ];
  };

  # nix-darwin skips user-agent cleanup once its last user agent is removed.
  # Its previous generation is still current while Home Manager activates.
  home.activation.retireNixDarwinAerospace =
    lib.hm.dag.entryBetween [ "onFilesChange" "setupLaunchAgents" ] [ "writeBoundary" ]
      ''
        (
          legacyPlist=${lib.escapeShellArg "${config.home.homeDirectory}/Library/LaunchAgents/org.nixos.aerospace.plist"}
          legacySource=/run/current-system/user/Library/LaunchAgents/org.nixos.aerospace.plist
          [[ -f "$legacySource" ]] || exit 0

          if [[ -e "$legacyPlist" || -L "$legacyPlist" ]]; then
            if /usr/bin/cmp -s "$legacySource" "$legacyPlist"; then
              :
            else
              comparisonStatus=$?
              if [[ "$comparisonStatus" -eq 1 ]]; then
                warnEcho "Preserving '$legacyPlist': it differs from the previous nix-darwin agent."
                exit 0
              fi
              errorEcho "Cannot compare '$legacyPlist' with the previous nix-darwin agent."
              exit "$comparisonStatus"
            fi
          fi

          bootoutArgs=()
          version="$(/usr/bin/sw_vers --productVersion)"
          if [[ "''${version%%.*}" -ge 26 ]]; then
            bootoutArgs=(--wait)
          fi
          if bootoutOutput="$(run /bin/launchctl bootout "''${bootoutArgs[@]}" "gui/$UID/org.nixos.aerospace" 2>&1)"; then
            if [[ "''${version%%.*}" -lt 26 ]]; then
              run sleep 1
            fi
          else
            bootoutStatus=$?
            # ESRCH means the previous agent is already unloaded.
            if [[ "$bootoutStatus" -ne 3 ]]; then
              errorEcho "Cannot stop the previous nix-darwin AeroSpace agent: $bootoutOutput"
              exit "$bootoutStatus"
            fi
          fi
          if [[ -e "$legacyPlist" || -L "$legacyPlist" ]]; then
            run /bin/rm -- "$legacyPlist"
          fi
        )
      '';

  targets.darwin.defaults."com.apple.dock" = lib.mkIf config.programs.aerospace.enable {
    mru-spaces = false;
    expose-group-apps = true;
  };

  home.activation.omarchySymbolicHotkeys = lib.mkIf config.programs.aerospace.enable (
    lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (id: shortcut: ''
            run /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
              -dict-add ${id} ${lib.escapeShellArg (lib.generators.toPlist { escape = true; } shortcut)}
          '')
          (
            # Carbon symbolic shortcuts take precedence over application hotkeys.
            # Disable only collisions; -dict-add preserves unrelated user shortcuts.
            lib.genAttrs
              [
                "27" # Cmd+grave: next window (scratchpad)
                "28"
                "29"
                "30"
                "31" # Cmd+Shift+3/4 screenshots (move to workspace)
                "64"
                "65" # Cmd+Space / Cmd+Alt+Space: Spotlight
                "184" # Cmd+Shift+5: screenshot toolbar (move to workspace)
              ]
              (_: {
                enabled = false;
              })
            // {
              "60" = disabledShortcut [
                32
                49
                1048576
              ];
              "61" = disabledShortcut [
                32
                49
                1572864
              ];
              "64" = disabledShortcut [
                65535
                49
                1048576
              ];
              "65" = disabledShortcut [
                65535
                49
                1572864
              ];
              "156" = disabledShortcut [
                65535
                49
                393216
              ];
            }
          )
      )}
    ''
  );
}
