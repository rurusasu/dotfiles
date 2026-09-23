{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  verifier = sets.wingetVerifyById."Microsoft.WSL";
in
{
  testMicrosoftWslVerifierContract = {
    expr = {
      inherit (verifier) command args timeoutSeconds recoveryStrategy;
    };
    expected = {
      command = "wsl";
      args = [ "--version" ];
      timeoutSeconds = 30;
      recoveryStrategy = "wingetRepairThenReinstall";
    };
  };
}
