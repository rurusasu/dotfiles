# User application choices, separate from nix-darwin's service ownership.
{
  lib,
  pkgs,
  aerospace,
  ghostty,
}:
let
  launch = app: "/usr/bin/open -a ${lib.escapeShellArg app}";
  cycles = import ./aerospace-cycle.nix {
    inherit lib;
    inherit (import ../../home/keybindings/bindings.nix { inherit lib; }) workspaces;
    executable = lib.getExe' aerospace "aerospace";
  };
in
{
  workspace-next = toString (pkgs.writeShellScript "omarchy-workspace-next" cycles.next);
  workspace-prev = toString (pkgs.writeShellScript "omarchy-workspace-prev" cycles.prev);
  terminal = "/usr/bin/open -na ${
    lib.escapeShellArg (if ghostty == null then "Ghostty" else "${ghostty}/Applications/Ghostty.app")
  }";
  browser = launch "Dia";
  files = launch "Finder";
  ai = launch "ChatGPT";
  passwords = launch "1Password";
  help = "${launch "TextEdit"} ${pkgs.writeText "omarchy-macos-keybindings.txt" (builtins.readFile ../../../docs/chezmoi/omarchy-macos.md)}";
  calculator = launch "Calculator";
  activity = launch "Activity Monitor";
}
