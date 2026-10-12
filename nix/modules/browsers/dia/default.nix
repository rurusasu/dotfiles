# Select the reviewed upstream package when the updater has promoted it.
{ pkgs }:
let
  candidate = (import ./provider-candidates.nix).dia-browser;
in
if candidate.source == "nixpkgs" then
  builtins.getAttr candidate.nixAttr pkgs
else
  pkgs.callPackage ./package.nix { }
