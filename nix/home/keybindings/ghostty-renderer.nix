# Pure Ghostty keybind renderer, shared by Home Manager and the JSON export.
{
  lib,
  bindings,
  asList ? false,
}:
let
  keybinds = map (
    binding:
    "${lib.concatStringsSep "+" (binding.modifiers ++ [ binding.key ])}=${
      if binding.action == "split-down" then
        "new_split:down"
      else if binding.action == "split-right" then
        "new_split:right"
      else if lib.hasPrefix "focus-" binding.action then
        "goto_split:${lib.removePrefix "focus-" binding.action}"
      else if lib.hasPrefix "resize-" binding.action then
        "resize_split:${lib.removePrefix "resize-" binding.action},${toString binding.amount}"
      else if binding.action == "new-tab" then
        "new_tab"
      else if binding.action == "previous-tab" then
        "previous_tab"
      else if binding.action == "next-tab" then
        "next_tab"
      else if binding.action == "goto-tab" then
        "goto_tab:${toString binding.amount}"
      else
        throw "Unknown shared Ghostty action: ${binding.action}"
    }"
  ) bindings;
in
if asList then
  keybinds
else
  lib.concatMapStringsSep "\n" (value: "keybind = ${value}") keybinds + "\n"
