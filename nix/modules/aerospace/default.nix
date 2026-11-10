{
  config,
  lib,
  pkgs,
  ...
}:
let
  aerospace = config.programs.aerospace.package;
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
  config = lib.mkMerge [
    { programs.aerospace.enable = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin true; }
    (lib.mkIf config.programs.aerospace.enable {
      programs.aerospace = {
        launchd.enable = true;
        settings = {
          config-version = 2;
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
              commands =
                (import ./darwin-commands.nix {
                  inherit lib pkgs aerospace;
                  ghostty = if config.programs.ghostty.enable then config.programs.ghostty.package else null;
                })
                // {
                  capture = "/usr/bin/open -a Screenshot";
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
      launchd.agents.aerospace.config = {
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

      targets.darwin.defaults."com.apple.dock" = {
        mru-spaces = false;
        expose-group-apps = true;
      };

      home.activation.omarchySymbolicHotkeys = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
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
                "64" = {
                  enabled = true;
                  value = {
                    parameters = [
                      65535
                      49
                      1048576
                    ];
                    type = "standard";
                  };
                };
                "65" = {
                  enabled = true;
                  value = {
                    parameters = [
                      65535
                      49
                      1572864
                    ];
                    type = "standard";
                  };
                };
                "156" = disabledShortcut [
                  65535
                  49
                  393216
                ];
              }
            )
        )}
      '';
    })
  ];
}
