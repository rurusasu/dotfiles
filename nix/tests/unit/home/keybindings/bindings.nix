{
  inputs,
  code,
}:
let
  inherit (inputs.nixpkgs) lib;
  aerospace = code.nix.modules.aerospace.aerospace {
    inherit lib;
    commands.terminal = "terminal --new-window";
  };
  hyprland = code.nix.modules.hyprland.hyprland-renderer {
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
    expr =
      lib.getAttrs
        [
          "SUPER + RETURN"
          "SUPER + 0"
          "SUPER + SHIFT + 0"
          "SUPER + SHIFT + ALT + 0"
          "SUPER + LEFT"
        ]
        (
          builtins.listToAttrs (
            map (binding: {
              name = builtins.head binding._args;
              value = (builtins.elemAt binding._args 1).expr;
            }) hyprland.bindings
          )
        );
    expected = {
      "SUPER + RETURN" = ''hl.dsp.exec_cmd("terminal --new-window")'';
      "SUPER + 0" = ''hl.dsp.focus({ workspace = "10" })'';
      "SUPER + SHIFT + 0" = ''hl.dsp.window.move({ workspace = "10" })'';
      "SUPER + SHIFT + ALT + 0" = ''hl.dsp.window.move({ workspace = "10", follow = false })'';
      "SUPER + LEFT" = ''hl.dsp.focus({ direction = "l" })'';
    };
  };
  testSharedKeysDoNotLoseBindingsDuringRendering = {
    expr =
      let
        contract = code.nix.home.keybindings.bindings { inherit lib; };
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
