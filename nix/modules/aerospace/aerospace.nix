# Pure renderer consumed by nix-darwin, not a Home Manager module.
{ lib, commands }:
let
  contract = import ../../home/keybindings/bindings.nix { inherit lib; };
  actions = {
    close = "close";
    floating = "layout floating tiling";
    split = "layout horizontal vertical";
    fullscreen = "fullscreen";
    tiled-fullscreen = "fullscreen";
    group = "layout accordion tiles";
    ungroup = "layout tiles";
    window-next = "focus --boundaries workspace --boundaries-action wrap-around-the-workspace dfs-next";
    window-prev = "focus --boundaries workspace --boundaries-action wrap-around-the-workspace dfs-prev";
    workspace-back = "workspace-back-and-forth";
    monitor-next = "focus-monitor --wrap-around next";
    monitor-prev = "focus-monitor --wrap-around prev";
    scratchpad = "workspace --auto-back-and-forth scratchpad";
    scratchpad-move = "move-node-to-workspace scratchpad";
    passthrough = "mode passthrough";
  }
  // lib.mapAttrs (_: command: "exec-and-forget ${command}") commands
  // lib.foldl' (
    acc: number:
    let
      workspace = toString number;
    in
    acc
    // {
      "workspace-${workspace}" = "workspace ${workspace}";
      "move-workspace-${workspace}" = "move-node-to-workspace --focus-follows-window ${workspace}";
      "send-workspace-${workspace}" = "move-node-to-workspace ${workspace}";
    }
  ) { } contract.workspaces
  // lib.foldl' (
    acc: direction:
    acc
    // {
      "focus-${direction}" = "focus ${direction}";
      "swap-${direction}" = "swap ${direction}";
      "move-monitor-${direction}" = "move-workspace-to-monitor ${direction}";
      "join-${direction}" = "join-with ${direction}";
    }
  ) { } contract.directions
  //
    lib.foldl'
      (
        acc: pixels:
        acc
        // {
          "width-minus-${pixels}" = "resize width -${pixels}";
          "width-plus-${pixels}" = "resize width +${pixels}";
          "height-minus-${pixels}" = "resize height -${pixels}";
          "height-plus-${pixels}" = "resize height +${pixels}";
        }
      )
      { }
      [
        "25"
        "100"
        "300"
      ];
  supported = builtins.filter (binding: builtins.hasAttr binding.action actions) contract.bindings;
in
{
  bindings = builtins.listToAttrs (
    map (
      binding:
      lib.nameValuePair (lib.concatStringsSep "-" (
        map (modifier: if modifier == "super" then "cmd" else modifier) binding.modifiers
        ++ [ (if binding.key == "escape" then "esc" else binding.key) ]
      )) actions.${binding.action}
    ) supported
  );
  unsupported = builtins.filter (
    binding: !(builtins.hasAttr binding.action actions)
  ) contract.bindings;
  inherit supported;
}
