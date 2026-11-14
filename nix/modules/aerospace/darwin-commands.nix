# User application choices, separate from nix-darwin's service ownership.
{
  lib,
  pkgs,
  aerospace,
  ghostty,
  chatgpt,
  dia,
  obsidian,
  onepassword,
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
  terminal = launch ghostty;
  browser = launch dia;
  files = launch "Finder";
  notes = launch obsidian;
  ai = launch chatgpt;
  passwords = launch onepassword;
  help = "${launch "TextEdit"} ${pkgs.writeText "omarchy-macos-keybindings.txt" (builtins.readFile ../../../docs/chezmoi/omarchy-macos.md)}";
  calculator = launch "Calculator";
  activity = launch "Activity Monitor";
}
