# User application choices, separate from nix-darwin's service ownership.
{
  lib,
  pkgs,
  aerospace,
}:
let
  launch = app: "/usr/bin/open -a ${lib.escapeShellArg app}";
  openUrl = url: "/usr/bin/open ${lib.escapeShellArg url}";
  help = pkgs.writeText "omarchy-macos-keybindings.txt" (
    builtins.readFile ../../../docs/chezmoi/omarchy-macos.md
  );
  contract = import ./bindings.nix { inherit lib; };
  cycles = import ./aerospace-cycle.nix {
    inherit lib;
    inherit (contract) workspaces;
    executable = lib.getExe' aerospace "aerospace";
  };
in
{
  workspace-next = toString (pkgs.writeShellScript "omarchy-workspace-next" cycles.next);
  workspace-prev = toString (pkgs.writeShellScript "omarchy-workspace-prev" cycles.prev);
  terminal = launch "WezTerm";
  browser = launch "Dia";
  files = launch "Finder";
  notes = launch "Obsidian";
  ai = launch "ChatGPT";
  passwords = launch "1Password";
  launcher = openUrl "raycast://";
  help = "${launch "TextEdit"} ${help}";
  calculator = launch "Calculator";
  activity = launch "Activity Monitor";
  clipboard = openUrl "raycast://extensions/raycast/clipboard-history/clipboard-history";
  emoji = openUrl "raycast://extensions/raycast/emoji-symbols/search-emoji-symbols";
}
