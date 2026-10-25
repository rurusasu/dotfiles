{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
  allocation = import ../../home/keybindings/bindings.nix { inherit lib; };
  aerospace = import ../../home/keybindings/aerospace.nix {
    inherit lib;
    commands.terminal = "terminal --new-window";
  };
  hyprland = import ../../home/keybindings/hyprland-renderer.nix {
    inherit lib;
    commands.terminal = "terminal --new-window";
  };
  chord = binding: lib.concatStringsSep "+" (binding.modifiers ++ [ binding.key ]);
  windowsGhosttyLines = lib.splitString "\n" allocation.windows.ghosttyConfig;
in
{
  testCommittedKeybindingsExportMatchesCanonicalAllocation = {
    expr = builtins.fromJSON (builtins.readFile ../../home/keybindings/generated.json);
    expected = allocation;
  };
  testGhosttyOmarchySplitNavigationAndTabActions = {
    expr = builtins.all (line: builtins.elem line (lib.splitString "\n" allocation.ghosttyConfig)) [
      "keybind = ctrl+shift+e=new_split:down"
      "keybind = ctrl+shift+o=new_split:right"
      "keybind = ctrl+alt+left=goto_split:left"
      "keybind = ctrl+alt+down=goto_split:down"
      "keybind = ctrl+alt+up=goto_split:up"
      "keybind = ctrl+alt+right=goto_split:right"
      "keybind = ctrl+shift+t=new_tab"
      "keybind = ctrl+shift+left=previous_tab"
      "keybind = ctrl+shift+up=previous_tab"
      "keybind = ctrl+shift+right=next_tab"
      "keybind = ctrl+shift+down=next_tab"
      "keybind = alt+1=goto_tab:1"
      "keybind = alt+9=goto_tab:9"
    ];
    expected = true;
  };
  testGhosttyResizeUsesPixelsForBothAmounts = {
    expr = builtins.all (line: builtins.elem line (lib.splitString "\n" allocation.ghosttyConfig)) [
      "keybind = super+ctrl+shift+left=resize_split:left,10"
      "keybind = super+ctrl+shift+down=resize_split:down,10"
      "keybind = super+ctrl+shift+up=resize_split:up,10"
      "keybind = super+ctrl+shift+right=resize_split:right,10"
      "keybind = super+ctrl+shift+alt+left=resize_split:left,100"
      "keybind = super+ctrl+shift+alt+down=resize_split:down,100"
      "keybind = super+ctrl+shift+alt+up=resize_split:up,100"
      "keybind = super+ctrl+shift+alt+right=resize_split:right,100"
    ];
    expected = true;
  };
  testGhosttyUnknownActionFailsInsteadOfDroppingKey = {
    expr =
      (builtins.tryEval (
        builtins.stringLength (
          import ../../home/keybindings/ghostty-renderer.nix {
            inherit lib;
            bindings = [
              {
                action = "unknown-action";
                key = "x";
                modifiers = [ "ctrl" ];
              }
            ];
          }
        )
      )).success;
    expected = false;
  };
  testWindowsGhosttyTransportPreservesAllCanonicalResizeSources = {
    expr = {
      sources = map (binding: binding.source) allocation.windows.ghosttyTransport;
      uniqueSources =
        builtins.length allocation.windows.ghosttyTransport == builtins.length (
          lib.unique (map (binding: chord binding.source) allocation.windows.ghosttyTransport)
        );
      onlyWslg = builtins.all (
        binding: binding.targetApp == "msrdc.exe"
      ) allocation.windows.ghosttyTransport;
    };
    expected = {
      sources = builtins.filter (binding: lib.hasPrefix "resize-" binding.action) allocation.ghostty;
      uniqueSources = true;
      onlyWslg = true;
    };
  };
  testWindowsGhosttyTransportUsesDistinctSuperFreeTargets = {
    expr = {
      targets = builtins.listToAttrs (
        map (binding: {
          name = binding.action;
          value = chord binding.target;
        }) allocation.windows.ghosttyTransport
      );
      uniqueTargets =
        builtins.length allocation.windows.ghosttyTransport == builtins.length (
          lib.unique (map (binding: chord binding.target) allocation.windows.ghosttyTransport)
        );
      noOtherGhosttyConflict = builtins.all (
        transport:
        !(builtins.elem (chord transport.target) (
          map chord (builtins.filter (binding: !(lib.hasPrefix "resize-" binding.action)) allocation.ghostty)
        ))
      ) allocation.windows.ghosttyTransport;
    };
    expected = {
      targets = {
        ghostty-resize-left-10 = "ctrl+alt+shift+left";
        ghostty-resize-down-10 = "ctrl+alt+shift+down";
        ghostty-resize-up-10 = "ctrl+alt+shift+up";
        ghostty-resize-right-10 = "ctrl+alt+shift+right";
        ghostty-resize-left-100 = "ctrl+alt+shift+home";
        ghostty-resize-down-100 = "ctrl+alt+shift+page_down";
        ghostty-resize-up-100 = "ctrl+alt+shift+page_up";
        ghostty-resize-right-100 = "ctrl+alt+shift+end";
      };
      uniqueTargets = true;
      noOtherGhosttyConflict = true;
    };
  };
  testWindowsGhosttyConfigChangesOnlyResizeTriggers = {
    expr = {
      resizeLines = builtins.filter (line: lib.hasInfix "=resize_split:" line) windowsGhosttyLines;
      otherLines = builtins.filter (line: !(lib.hasInfix "=resize_split:" line)) windowsGhosttyLines;
    };
    expected = {
      resizeLines = [
        "keybind = ctrl+alt+shift+left=resize_split:left,10"
        "keybind = ctrl+alt+shift+home=resize_split:left,100"
        "keybind = ctrl+alt+shift+down=resize_split:down,10"
        "keybind = ctrl+alt+shift+page_down=resize_split:down,100"
        "keybind = ctrl+alt+shift+up=resize_split:up,10"
        "keybind = ctrl+alt+shift+page_up=resize_split:up,100"
        "keybind = ctrl+alt+shift+right=resize_split:right,10"
        "keybind = ctrl+alt+shift+end=resize_split:right,100"
      ];
      otherLines = builtins.filter (line: !(lib.hasInfix "=resize_split:" line)) (
        lib.splitString "\n" allocation.ghosttyConfig
      );
    };
  };
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
        contract = import ../../home/keybindings/bindings.nix { inherit lib; };
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
