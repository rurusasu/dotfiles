{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
  legacyCommands = [
    "hermes-docker"
    "hermes-desktop-docker"
  ];
  check = system:
    let
      pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs system;
      sets = import ../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      selected = sets.darwinHomePackagesForInstallFeatures [ "WithHermes" ];
    in
    builtins.filter (package: builtins.elem package.name legacyCommands) selected;
in
{
  testNativeHermesProfileDoesNotInstallDockerGatewayAdapters = {
    expr = builtins.map check systems;
    expected = [ [ ] [ ] [ ] ];
  };
}
