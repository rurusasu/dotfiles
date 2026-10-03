{
  config,
  lib,
  pkgs,
  ...
}:
let
  sets = import ../../packages/sets.nix { inherit pkgs lib; };
  aerospace = builtins.head (sets.resolveForInstallFeatures [ ] [ "aerospace" ]);
  openUrl = url: "/usr/bin/open ${lib.escapeShellArg url}";
  contract = import ../../home/keybindings/bindings.nix { inherit lib; };
  rendered = import ../../home/keybindings/aerospace.nix {
    inherit lib;
    commands = (import ../../home/keybindings/darwin-commands.nix { inherit lib pkgs aerospace; }) // {
      capture = "/usr/bin/open -a Screenshot";
      lock = openUrl "raycast://extensions/raycast/system/lock-screen";
      audio = openUrl "x-apple.systempreferences:com.apple.Sound-Settings.extension";
      bluetooth = openUrl "x-apple.systempreferences:com.apple.BluetoothSettings";
      display = openUrl "x-apple.systempreferences:com.apple.Displays-Settings.extension";
      network = openUrl "x-apple.systempreferences:com.apple.wifi-settings-extension";
      power = openUrl "x-apple.systempreferences:com.apple.Battery-Settings.extension";
    };
  };
  # Carbon symbolic shortcuts take precedence over application hotkeys.
  # Disable only collisions; -dict-add preserves unrelated user shortcuts.
  symbolicHotkeys = [
    "27" # Cmd+grave: next window (scratchpad)
    "28"
    "29"
    "30"
    "31" # Cmd+Shift+3/4 screenshots (move to workspace)
    "64"
    "65" # Cmd+Space / Cmd+Alt+Space: Spotlight
    "184" # Cmd+Shift+5: screenshot toolbar (move to workspace)
  ];
in
{
  services.aerospace = {
    enable = true;
    package = aerospace;
    settings = {
      config-version = 2;
      start-at-login = false; # nix-darwin's launchd agent owns the process.
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      key-mapping.preset = "qwerty";
      persistent-workspaces = map toString contract.workspaces;
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
      mode.main.binding = rendered.bindings;
      mode.passthrough.binding.cmd-ctrl-alt-esc = "mode main";
    };
  };

  system.defaults.dock = lib.mkIf config.services.aerospace.enable {
    mru-spaces = false;
    expose-group-apps = true;
  };

  system.activationScripts.omarchySymbolicHotkeys.text = lib.mkIf config.services.aerospace.enable ''
    uid="$(id -u -- ${lib.escapeShellArg config.system.primaryUser})"
    ${lib.concatMapStringsSep "\n" (id: ''
      launchctl asuser "$uid" sudo --user=${lib.escapeShellArg config.system.primaryUser} -- \
        /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
        -dict-add ${id} '<dict><key>enabled</key><false/></dict>'
    '') symbolicHotkeys}
  '';
}
