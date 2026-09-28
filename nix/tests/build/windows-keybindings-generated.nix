{ pkgs }:
let
  generated = import ../../hosts/windows/export.nix {
    inherit pkgs;
    inherit (pkgs) lib;
  };
  settings = import ../../hosts/windows/omarchy-keybindings.nix { inherit (pkgs) lib; };
in
pkgs.runCommand "windows-keybindings-generated-check" { } (
  pkgs.lib.concatMapStringsSep "\n" (path: ''
    diff -u ${generated}/${pkgs.lib.escapeShellArg path} ${../../../chezmoi}/${pkgs.lib.escapeShellArg path}
  '') (builtins.attrNames settings.artifacts)
  + ''
    touch "$out"
  ''
)
