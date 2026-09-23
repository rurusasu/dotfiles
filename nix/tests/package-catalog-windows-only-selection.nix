{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
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
    "OpenAI.Codex"
    "Oven-sh.Bun"
    "zig.zig"
  ];
in
{
  testCrossPlatformWingetPackagesAreNotWindowsOnly = {
    expr =
      builtins.filter
        (packageId: builtins.elem packageId sets.windowsOnly.winget)
        crossPlatformWingetIds;
    expected = [ ];
  };
}
