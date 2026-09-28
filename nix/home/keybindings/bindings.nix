# Shared user key allocation; contains no OS services or Home Manager options.
{ lib }:
let
  bind = action: key: modifiers: { inherit action key modifiers; };
  super = [ "super" ];
  shifted = [
    "super"
    "shift"
  ];
  control = [
    "super"
    "ctrl"
  ];
  alt = [
    "super"
    "alt"
  ];
  directions = [
    "left"
    "down"
    "up"
    "right"
  ];
  workspaces = lib.range 1 10;
  bindings = [
    (bind "terminal" "enter" super)
    (bind "browser" "enter" shifted)
    (bind "browser" "b" shifted)
    (bind "files" "f" shifted)
    (bind "notes" "o" shifted)
    (bind "ai" "a" shifted)
    (bind "passwords" "slash" shifted)
    (bind "launcher" "space" super)
    (bind "launcher" "space" alt)
    (bind "help" "k" super)
    (bind "close" "w" super)
    (bind "close" "q" super)
    (bind "floating" "t" super)
    (bind "split" "j" super)
    (bind "fullscreen" "f" super)
    (bind "tiled-fullscreen" "f" control)
    (bind "group" "g" super)
    (bind "ungroup" "g" alt)
    (bind "window-next" "tab" [ "alt" ])
    (bind "window-prev" "tab" [
      "alt"
      "shift"
    ])
    (bind "workspace-next" "tab" super)
    (bind "workspace-prev" "tab" shifted)
    (bind "workspace-back" "tab" control)
    (bind "monitor-next" "tab" [
      "ctrl"
      "alt"
    ])
    (bind "monitor-prev" "tab" [
      "ctrl"
      "alt"
      "shift"
    ])
    (bind "scratchpad" "s" super)
    (bind "scratchpad" "backtick" super)
    (bind "scratchpad-move" "s" alt)
    (bind "scratchpad-move" "backtick" shifted)
    (bind "capture" "c" control)
    (bind "calculator" "q" control)
    (bind "activity" "t" control)
    (bind "lock" "l" control)
    (bind "clipboard" "v" control)
    (bind "emoji" "e" control)
    (bind "audio" "a" control)
    (bind "bluetooth" "b" control)
    (bind "display" "d" control)
    (bind "network" "w" control)
    (bind "power" "p" control)
    (bind "passthrough" "escape" [
      "super"
      "ctrl"
      "alt"
    ])
  ]
  ++ lib.concatMap (
    number:
    let
      workspace = toString number;
      key = if number == 10 then "0" else workspace;
    in
    [
      (bind "workspace-${workspace}" key super)
      (bind "move-workspace-${workspace}" key shifted)
      (bind "send-workspace-${workspace}" key [
        "super"
        "shift"
        "alt"
      ])
    ]
  ) workspaces
  ++ lib.concatMap (direction: [
    (bind "focus-${direction}" direction super)
    (bind "swap-${direction}" direction shifted)
    (bind "move-monitor-${direction}" direction [
      "super"
      "shift"
      "alt"
    ])
    (bind "join-${direction}" direction alt)
  ]) directions
  ++
    lib.concatMap
      (step: [
        (bind "width-minus-${step.pixels}" "minus" (super ++ step.modifiers))
        (bind "width-plus-${step.pixels}" "equal" (super ++ step.modifiers))
        (bind "height-minus-${step.pixels}" "minus" (shifted ++ step.modifiers))
        (bind "height-plus-${step.pixels}" "equal" (shifted ++ step.modifiers))
      ])
      [
        {
          pixels = "100";
          modifiers = [ ];
        }
        {
          pixels = "25";
          modifiers = [ "alt" ];
        }
        {
          pixels = "300";
          modifiers = [ "ctrl" ];
        }
      ];
  chord =
    binding:
    lib.concatStringsSep "+" ((lib.sort builtins.lessThan binding.modifiers) ++ [ binding.key ]);
in
assert builtins.length bindings == builtins.length (lib.unique (map chord bindings));
{
  inherit bindings directions workspaces;
}
