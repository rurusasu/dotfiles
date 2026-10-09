# Shared derivation adapters used by catalog categories.
{ pkgs }:
let
  # The same appearance data is consumed by chezmoi templates and exposed to
  # Nix consumers so font/theme values do not drift by platform.
  inherit ((builtins.fromJSON (builtins.readFile ../../../chezmoi/.chezmoidata/appearance.json)))
    appearance
    ;
  darwinProviderCandidates = import ../darwin-provider-candidates.nix;
  darwinProviderCandidate = name: darwinProviderCandidates.${name};
  selectDarwinPackage =
    name: customPackage:
    let
      candidate = darwinProviderCandidate name;
    in
    if candidate.source == "nixpkgs" then builtins.getAttr candidate.nixAttr pkgs else customPackage;
in
{
  inherit
    appearance
    selectDarwinPackage
    darwinProviderCandidate
    ;
}
