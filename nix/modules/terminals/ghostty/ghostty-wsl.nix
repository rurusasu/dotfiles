# WSLg receives these Ghostty-local chords directly, without a Windows key hook.
{ lib, bindings }:
import ./ghostty-renderer.nix {
  inherit lib;
  bindings = map (
    binding:
    binding
    // lib.optionalAttrs (lib.hasPrefix "resize-" binding.action) {
      key =
        if binding.amount == 10 then
          binding.key
        else if binding.amount == 100 then
          {
            left = "home";
            down = "page_down";
            up = "page_up";
            right = "end";
          }
          .${lib.removePrefix "resize-" binding.action}
        else
          throw "Unsupported WSL Ghostty resize amount: ${toString binding.amount}";
      modifiers = [
        "ctrl"
        "alt"
        "shift"
      ];
    }
  ) bindings;
}
