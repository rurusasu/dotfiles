{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
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
      inherit (verifier)
        command
        args
        timeoutSeconds
        recoveryStrategy
        ;
    };
    expected = {
      command = "wsl";
      args = [ "--version" ];
      timeoutSeconds = 30;
      recoveryStrategy = "wingetRepairThenReinstall";
    };
  };
}
