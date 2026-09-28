{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
  aerospace = import ../home/keybindings/aerospace.nix {
    inherit lib;
    commands.terminal = "terminal --new-window";
  };
  hyprland = import ../home/keybindings/hyprland-renderer.nix {
    inherit lib;
    commands.terminal = "terminal --new-window";
  };
in
{
  testSharedKeysTranslateModifiersAndWorkspaceZero = {
    expr = lib.getAttrs [
      "cmd-enter"
      "cmd-0"
      "cmd-shift-0"
      "cmd-shift-alt-0"
      "cmd-ctrl-alt-esc"
    ] aerospace.bindings;
    expected = {
      cmd-enter = "exec-and-forget terminal --new-window";
      cmd-0 = "workspace 10";
      cmd-shift-0 = "move-node-to-workspace --focus-follows-window 10";
      cmd-shift-alt-0 = "move-node-to-workspace 10";
      cmd-ctrl-alt-esc = "mode passthrough";
    };
  };
  testSharedKeysPublishMissingCommandsInsteadOfBrokenBindings = {
    expr = {
      browserMissing = builtins.elem "browser" (map (binding: binding.action) aerospace.unsupported);
      noBrowserKey = !(aerospace.bindings ? cmd-shift-b);
      nativeClipboardNotOverridden = !(aerospace.bindings ? cmd-c);
      terminalSupported = builtins.elem "terminal" (map (binding: binding.action) aerospace.supported);
    };
    expected = {
      browserMissing = true;
      noBrowserKey = true;
      nativeClipboardNotOverridden = true;
      terminalSupported = true;
    };
  };
  testSharedHyprlandKeysProduceDistinctFollowAndSilentCommands = {
    expr = builtins.all (line: lib.hasInfix line hyprland.config) [
      ''hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("terminal --new-window"),''
      ''hl.bind("SUPER + 0", hl.dsp.focus({ workspace = "10" }),''
      ''hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = "10" }),''
      ''hl.bind("SUPER + SHIFT + ALT + 0", hl.dsp.window.move({ workspace = "10", follow = false }),''
      ''hl.bind("SUPER + LEFT", hl.dsp.focus({ direction = "l" }),''
    ];
    expected = true;
  };
  testSharedKeysDoNotLoseBindingsDuringRendering = {
    expr =
      let
        contract = import ../home/keybindings/bindings.nix { inherit lib; };
      in
      {
        uniqueAerospace =
          builtins.length (builtins.attrNames aerospace.bindings) == builtins.length aerospace.supported;
        accountedAerospace =
          builtins.length (aerospace.supported ++ aerospace.unsupported) == builtins.length contract.bindings;
        accountedHyprland =
          builtins.length (hyprland.supported ++ hyprland.unsupported) == builtins.length contract.bindings;
      };
    expected = {
      uniqueAerospace = true;
      accountedAerospace = true;
      accountedHyprland = true;
    };
  };
}
