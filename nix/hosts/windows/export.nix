# Windows can consume these checked-in artifacts without installing Nix.
{ pkgs, lib }:
let
  settings = import ./omarchy-keybindings.nix { inherit lib; };
in
pkgs.runCommand "windows-keybindings-export" { nativeBuildInputs = [ pkgs.oxfmt ]; } (
  lib.concatStringsSep "\n" (
    lib.mapAttrsToList (path: content: ''
      install -Dm644 ${pkgs.writeText (builtins.baseNameOf path) content} "$out"/${lib.escapeShellArg path}
    '') settings.artifacts
  )
  + ''
    oxfmt --write "$out/dot_glzr/glazewm/config.json"
  ''
)
