{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testDirectInstallersUseSharedBudget = {
    expr = builtins.mapAttrs (_: installer: installer.timeoutSeconds) sets.wingetDirectInstallers;
    expected = {
      chezmoi = 3600;
      direnv = 3600;
      dprint = 3600;
      "eza-community.eza" = 3600;
      fd = 3600;
    };
  };

  testNoPnpmPackagesAreDeclared = {
    expr = {
      packages = sets.pnpmGlobal;
      args = sets.pnpmInstallArgs;
    };
    expected = {
      packages = [ ];
      args = { };
    };
  };
}
