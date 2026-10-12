{ inputs }:
let
  darwin = (import ../fixtures/packages.nix { inherit inputs; }).darwin.config;
in
{
  testHermesDesktopIsNotInstalledThroughHomebrewCask = {
    expr = builtins.any (cask: cask.name == "hermes-desktop") darwin.homebrew.casks;
    expected = false;
  };
}
