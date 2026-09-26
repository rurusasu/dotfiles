{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs system;
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  crossPlatformWingetIds = [
    "Docker.DockerDesktop"
    "dprint.dprint"
    "hadolint.hadolint"
    "Google.Chrome"
    "Oven-sh.Bun"
    "zig.zig"
  ];
in
{
  testCrossPlatformWingetPackagesAreNotWindowsOnly = {
    expr = builtins.filter (
      packageId: builtins.elem packageId sets.windowsOnly.winget
    ) crossPlatformWingetIds;
    expected = [ ];
  };
}
