{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
  renderer = import ../../home/keybindings/glazewm.nix {
    inherit lib;
    commands.terminal = "terminal.exe";
  };
  host = import ../../hosts/windows/omarchy-keybindings.nix { inherit lib; };
  find =
    chord:
    builtins.head (
      builtins.filter (binding: builtins.elem chord binding.bindings) renderer.config.keybindings
    );
  contract = import ../../home/keybindings/bindings.nix { inherit lib; };
in
{
  testWindowsBothSuperKeysAndWorkspaceTen = {
    expr = {
      terminal = find "lwin+enter";
      workspace = find "rwin+0";
      follow = (find "lwin+shift+0").commands;
      silent = (find "rwin+shift+alt+0").commands;
    };
    expected = {
      terminal = {
        bindings = [
          "lwin+enter"
          "rwin+enter"
        ];
        commands = [ "shell-exec terminal.exe" ];
      };
      workspace = {
        bindings = [
          "lwin+0"
          "rwin+0"
        ];
        commands = [ "focus --workspace 10" ];
      };
      follow = [
        "move --workspace 10"
        "focus --workspace 10"
      ];
      silent = [ "move --workspace 10" ];
    };
  };
  testWindowsEmptyWorkspacesAndPixelResize = {
    expr = {
      workspaces = renderer.config.workspaces;
      next = (find "lwin+tab").commands;
      previous = (find "rwin+shift+tab").commands;
      resize = (find "lwin+control+oem_minus").commands;
      focus = (find "rwin+left").commands;
    };
    expected = {
      workspaces =
        map
          (name: {
            inherit name;
            keep_alive = true;
          })
          [
            "1"
            "2"
            "3"
            "4"
            "5"
            "6"
            "7"
            "8"
            "9"
            "10"
          ];
      next = [ "focus --next-workspace" ];
      previous = [ "focus --prev-workspace" ];
      resize = [ "resize --width -300px" ];
      focus = [ "focus --direction left" ];
    };
  };
  testWindowsAccountsForUnsupportedSemantics = {
    expr = {
      count = builtins.length (renderer.supported ++ renderer.unsupported);
      group =
        (builtins.head (builtins.filter (binding: binding.action == "group") renderer.unsupported)).reason;
      missingBrowser = builtins.any (
        binding: binding.action == "browser" && binding.reason != ""
      ) renderer.unsupported;
      noWinLockOverride = builtins.all (
        binding: !(builtins.elem "lwin+l" binding.bindings || builtins.elem "rwin+l" binding.bindings)
      ) renderer.config.keybindings;
      unique =
        let
          chords = lib.concatMap (binding: binding.bindings) renderer.config.keybindings;
        in
        builtins.length chords == builtins.length (lib.unique chords);
    };
    expected = {
      count = builtins.length contract.bindings;
      group = "GlazeWM does not provide grouped/tabbed containers.";
      missingBrowser = true;
      noWinLockOverride = true;
      unique = true;
    };
  };
  testWindowsHostExportsOnlyWindowsTransport = {
    expr = {
      enabled = host.enable;
      config = builtins.fromJSON host.artifacts."dot_glzr/glazewm/config.json";
      scripts = builtins.all (name: host.artifacts.${name} != "") [
        "dot_glzr/glazewm/actions.ps1"
        "dot_glzr/glazewm/start-glazewm.ps1"
      ];
      accounted = builtins.length (host.supported ++ host.unsupported);
    };
    expected = {
      enabled = true;
      config = host.config;
      scripts = true;
      accounted = builtins.length contract.bindings;
    };
  };
}
