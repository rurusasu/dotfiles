# Pure renderer; hyprland.nix owns the Home Manager options.
{ lib, commands }:
let
  contract = import ./bindings.nix { inherit lib; };
  quote = builtins.toJSON;
  actions = {
    close = "hl.dsp.window.close()";
    floating = ''hl.dsp.window.float({ action = "toggle" })'';
    split = ''hl.dsp.layout("togglesplit")'';
    fullscreen = ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'';
    tiled-fullscreen = ''hl.dsp.window.fullscreen({ mode = "maximized" })'';
    group = "hl.dsp.group.toggle()";
    ungroup = "hl.dsp.window.move({ out_of_group = true })";
    window-next = "hl.dsp.window.cycle_next()";
    window-prev = "hl.dsp.window.cycle_next({ next = false })";
    workspace-next = ''hl.dsp.focus({ workspace = "e+1" })'';
    workspace-prev = ''hl.dsp.focus({ workspace = "e-1" })'';
    workspace-back = ''hl.dsp.focus({ workspace = "previous" })'';
    monitor-next = ''hl.dsp.focus({ monitor = "+1" })'';
    monitor-prev = ''hl.dsp.focus({ monitor = "-1" })'';
    scratchpad = ''hl.dsp.workspace.toggle_special("scratchpad")'';
    scratchpad-move = ''hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })'';
  }
  // lib.mapAttrs (_: command: "hl.dsp.exec_cmd(${quote command})") commands
  // lib.foldl' (
    acc: number:
    let
      workspace = quote (toString number);
    in
    acc
    // {
      "workspace-${toString number}" = "hl.dsp.focus({ workspace = ${workspace} })";
      "move-workspace-${toString number}" = "hl.dsp.window.move({ workspace = ${workspace} })";
      "send-workspace-${toString number}" =
        "hl.dsp.window.move({ workspace = ${workspace}, follow = false })";
    }
  ) { } contract.workspaces
  // lib.foldl' (
    acc: direction:
    let
      short = quote (builtins.substring 0 1 direction);
    in
    acc
    // {
      "focus-${direction}" = "hl.dsp.focus({ direction = ${short} })";
      "swap-${direction}" = "hl.dsp.window.swap({ direction = ${short} })";
      "move-monitor-${direction}" = "hl.dsp.workspace.move({ monitor = ${short} })";
      "join-${direction}" = "hl.dsp.window.move({ into_group = ${short} })";
    }
  ) { } contract.directions
  //
    lib.foldl'
      (
        acc: pixels:
        acc
        // {
          "width-minus-${pixels}" = "hl.dsp.window.resize({ x = -${pixels}, y = 0, relative = true })";
          "width-plus-${pixels}" = "hl.dsp.window.resize({ x = ${pixels}, y = 0, relative = true })";
          "height-minus-${pixels}" = "hl.dsp.window.resize({ x = 0, y = -${pixels}, relative = true })";
          "height-plus-${pixels}" = "hl.dsp.window.resize({ x = 0, y = ${pixels}, relative = true })";
        }
      )
      { }
      [
        "25"
        "100"
        "300"
      ];
  keyName =
    key:
    {
      enter = "RETURN";
      backtick = "grave";
    }
    .${key} or (lib.toUpper key);
  chord =
    binding:
    lib.concatStringsSep " + " (map lib.toUpper binding.modifiers ++ [ (keyName binding.key) ]);
  supported = builtins.filter (binding: builtins.hasAttr binding.action actions) contract.bindings;
in
{
  config =
    lib.concatMapStringsSep "\n" (
      binding:
      "hl.bind(${quote (chord binding)}, ${actions.${binding.action}}, { description = ${quote binding.action} })"
    ) supported
    + "\n";
  unsupported = builtins.filter (
    binding: !(builtins.hasAttr binding.action actions)
  ) contract.bindings;
  inherit supported;
}
