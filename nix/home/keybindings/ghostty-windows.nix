# WSLg does not deliver Windows-key resize chords to Ghostty. PowerToys translates
# the canonical chords only in msrdc.exe; Ghostty receives these private chords.
{ lib, bindings }:
let
  largeResizeKeys = {
    left = "home";
    down = "page_down";
    up = "page_up";
    right = "end";
  };
  transport = map (
    binding:
    let
      direction = lib.removePrefix "resize-" binding.action;
    in
    {
      action = "ghostty-${binding.action}-${toString binding.amount}";
      source = binding;
      target = {
        key =
          if binding.amount == 10 then
            binding.key
          else if binding.amount == 100 then
            largeResizeKeys.${direction}
          else
            throw "Unsupported Windows Ghostty resize amount: ${toString binding.amount}";
        modifiers = [
          "ctrl"
          "alt"
          "shift"
        ];
      };
      targetApp = "msrdc.exe";
    }
  ) (builtins.filter (binding: lib.hasPrefix "resize-" binding.action) bindings);
  transportBinding =
    binding:
    let
      remap = lib.findFirst (item: item.source == binding) null transport;
    in
    binding // lib.optionalAttrs (remap != null) remap.target;
in
{
  inherit transport;
  config = import ./ghostty-renderer.nix {
    inherit lib;
    bindings = map transportBinding bindings;
  };
}
