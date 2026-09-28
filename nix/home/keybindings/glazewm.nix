# Pure Windows renderer. The host selects deployment and startup ownership.
{ lib, commands }:
let
  contract = import ./bindings.nix { inherit lib; };
  actions = {
    close = [ "close" ];
    floating = [ "toggle-floating --centered" ];
    split = [ "toggle-tiling-direction" ];
    fullscreen = [ "toggle-fullscreen --maximized=false" ];
    tiled-fullscreen = [ "toggle-fullscreen --maximized=true" ];
    workspace-next = [ "focus --next-workspace" ];
    workspace-prev = [ "focus --prev-workspace" ];
    workspace-back = [ "focus --recent-workspace" ];
    passthrough = [ "wm-toggle-pause" ];
  }
  // lib.mapAttrs (_: command: [ "shell-exec ${command}" ]) commands
  // lib.foldl' (
    acc: number:
    let
      workspace = toString number;
    in
    acc
    // {
      "workspace-${workspace}" = [ "focus --workspace ${workspace}" ];
      "move-workspace-${workspace}" = [
        "move --workspace ${workspace}"
        "focus --workspace ${workspace}"
      ];
      "send-workspace-${workspace}" = [ "move --workspace ${workspace}" ];
    }
  ) { } contract.workspaces
  // lib.foldl' (
    acc: direction:
    acc
    // {
      "focus-${direction}" = [ "focus --direction ${direction}" ];
    }
  ) { } contract.directions
  //
    lib.foldl'
      (
        acc: pixels:
        acc
        // {
          "width-minus-${pixels}" = [ "resize --width -${pixels}px" ];
          "width-plus-${pixels}" = [ "resize --width +${pixels}px" ];
          "height-minus-${pixels}" = [ "resize --height -${pixels}px" ];
          "height-plus-${pixels}" = [ "resize --height +${pixels}px" ];
        }
      )
      { }
      [
        "25"
        "100"
        "300"
      ];
  reasons = {
    group = "GlazeWM does not provide grouped/tabbed containers.";
    ungroup = "GlazeWM does not provide grouped/tabbed containers.";
    scratchpad = "GlazeWM does not provide a hidden scratchpad workspace.";
    scratchpad-move = "GlazeWM does not provide a hidden scratchpad workspace.";
    window-next = "Windows handles Alt+Tab natively; no global binding is registered.";
    window-prev = "Windows handles Alt+Shift+Tab natively; no global binding is registered.";
    monitor-next = "GlazeWM requires an explicit monitor index; monitor cycling is not configured.";
    monitor-prev = "GlazeWM requires an explicit monitor index; monitor cycling is not configured.";
  }
  // builtins.listToAttrs (
    lib.concatMap (direction: [
      (lib.nameValuePair "swap-${direction}" "GlazeWM directional move does not guarantee an exact window swap.")
      (lib.nameValuePair "join-${direction}" "GlazeWM does not provide grouped/tabbed containers.")
      (lib.nameValuePair "move-monitor-${direction}" "GlazeWM moves whole workspaces between monitors; focused-window monitor moves are not configured.")
    ]) contract.directions
  );
  reserved = binding: binding.key == "l" && binding.modifiers == [ "super" ];
  supported = builtins.filter (
    binding: builtins.hasAttr binding.action actions && !(reserved binding)
  ) contract.bindings;
  keyName =
    key:
    {
      slash = "oem_question";
      backtick = "oem_tilde";
      minus = "oem_minus";
      equal = "oem_plus";
    }
    .${key} or key;
  chords =
    binding:
    map
      (
        win:
        lib.concatStringsSep "+" (
          map (
            modifier:
            {
              super = win;
              ctrl = "control";
            }
            .${modifier} or modifier
          ) binding.modifiers
          ++ [ (keyName binding.key) ]
        )
      )
      (
        if builtins.elem "super" binding.modifiers then
          [
            "lwin"
            "rwin"
          ]
        else
          [ "lwin" ]
      );
in
{
  inherit supported;
  unsupported =
    map
      (
        binding:
        binding
        // {
          reason =
            if reserved binding then
              "Windows reserves Win+L for secure workstation locking."
            else
              reasons.${binding.action} or "No Windows command is configured for this action.";
        }
      )
      (
        builtins.filter (
          binding: !(builtins.hasAttr binding.action actions) || reserved binding
        ) contract.bindings
      );
  config = {
    general = {
      startup_commands = [ ];
      shutdown_commands = [ ];
      config_reload_commands = [ ];
      focus_follows_cursor = false;
      toggle_workspace_on_refocus = false;
      hide_method = "cloak";
      show_all_in_taskbar = false;
    };
    gaps = {
      inner_gap = "8px";
      outer_gap = {
        top = "8px";
        right = "8px";
        bottom = "8px";
        left = "8px";
      };
    };
    window_behavior.initial_state = "tiling";
    workspaces = map (number: {
      name = toString number;
      keep_alive = true;
    }) contract.workspaces;
    keybindings = map (binding: {
      bindings = chords binding;
      commands = actions.${binding.action};
    }) supported;
    window_rules = [ ];
    binding_modes = [ ];
  };
}
