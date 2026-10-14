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
    (bind "browser-private" "b" (shifted ++ [ "alt" ]))
    (bind "files" "f" shifted)
    (bind "activity" "t" shifted)
    (bind "music" "m" shifted)
    (bind "notes" "o" shifted)
    (bind "editor" "n" shifted)
    (bind "calendar" "c" shifted)
    (bind "email" "e" shifted)
    (bind "ai" "a" shifted)
    (bind "passwords" "slash" shifted)
    (bind "messenger-signal" "g" shifted)
    (bind "messenger-google" "g" (shifted ++ [ "ctrl" ]))
    (bind "messenger-whatsapp" "g" (shifted ++ [ "alt" ]))
    (bind "docker" "d" shifted)
    (bind "copy" "c" super)
    (bind "cut" "x" super)
    (bind "paste" "v" super)
    (bind "screenshot" "print" [ ])
    (bind "screenshot-clipboard" "print" [ "shift" ])
    (bind "record" "print" [ "alt" ])
    (bind "color-picker" "print" super)
    (bind "save-browser-url" "l" [
      "alt"
      "shift"
    ])
    (bind "notification-dismiss" "comma" super)
    (bind "notification-dismiss-all" "comma" shifted)
    (bind "notification-toggle" "comma" control)
    (bind "notification-history" "comma" alt)
    (bind "theme-cycle" "space" (control ++ [ "shift" ]))
    (bind "background-cycle" "space" control)
    (bind "transparency-toggle" "backspace" super)
    (bind "idle-toggle" "i" control)
    (bind "night-mode-toggle" "n" control)
    (bind "bar-toggle" "space" shifted)
    (bind "audio-output-cycle" "mute" super)
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
  ghostty = import ./ghostty.nix { inherit lib directions; };
  ghosttyWindows = import ./ghostty-windows.nix {
    inherit lib;
    bindings = ghostty;
  };
  neovim = import ./neovim.nix;
  windowsActions = [
    "terminal"
    "browser"
    "browser-private"
    "files"
    "activity"
    "music"
    "notes"
    "editor"
    "calendar"
    "email"
    "ai"
    "passwords"
    "messenger-signal"
    "messenger-google"
    "messenger-whatsapp"
    "docker"
    "copy"
    "cut"
    "paste"
    "clipboard"
    "screenshot"
    "screenshot-clipboard"
    "record"
    "color-picker"
    "save-browser-url"
    "notification-dismiss"
    "notification-dismiss-all"
    "notification-toggle"
    "notification-history"
    "theme-cycle"
    "background-cycle"
    "transparency-toggle"
    "idle-toggle"
    "night-mode-toggle"
    "bar-toggle"
    "audio-output-cycle"
  ];
  chord =
    binding:
    lib.concatStringsSep "+" ((lib.sort builtins.lessThan binding.modifiers) ++ [ binding.key ]);
in
assert builtins.length bindings == builtins.length (lib.unique (map chord bindings));
{
  inherit
    bindings
    directions
    workspaces
    ghostty
    neovim
    ;
  neovimLeader = " ";
  ghosttyConfig = import ./ghostty-renderer.nix {
    inherit lib;
    bindings = ghostty;
  };
  windows = {
    bindings = builtins.filter (binding: builtins.elem binding.action windowsActions) bindings;
    ghosttyTransport = ghosttyWindows.transport;
    ghosttyConfig = ghosttyWindows.config;
    disabledShortcuts = [
      {
        key = "d";
        modifiers = super;
      }
    ];
  };
}
