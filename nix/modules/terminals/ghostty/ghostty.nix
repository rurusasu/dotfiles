# Application key allocation; consumed by Home Manager and the Windows export.
{ lib, directions }:
let
  bind = action: key: modifiers: { inherit action key modifiers; };
  controlShift = [
    "ctrl"
    "shift"
  ];
  resizeModifiers = [
    "super"
    "ctrl"
    "shift"
  ];
in
[
  (bind "split-down" "e" controlShift)
  (bind "split-right" "o" controlShift)
  (bind "new-tab" "t" controlShift)
  (bind "previous-tab" "left" controlShift)
  (bind "previous-tab" "up" controlShift)
  (bind "next-tab" "right" controlShift)
  (bind "next-tab" "down" controlShift)
]
++ lib.concatMap (direction: [
  (bind "focus-${direction}" direction [
    "ctrl"
    "alt"
  ])
  ((bind "resize-${direction}" direction resizeModifiers) // { amount = 10; })
  ((bind "resize-${direction}" direction (resizeModifiers ++ [ "alt" ])) // { amount = 100; })
]) directions
++ map (number: (bind "goto-tab" (toString number) [ "alt" ]) // { amount = number; }) (
  lib.range 1 9
)
