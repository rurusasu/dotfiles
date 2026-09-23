{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testCodexDesktopUsesAppxLaunchTargetVerifier = {
    expr = sets.msstoreVerifyById."9PLM9XGG6VKS";
    expected = {
      type = "appxLaunchTarget";
      command = "OpenAI.Codex";
      args = [ "OpenAI.Codex_2p2nqsd0c76g0!App" ];
    };
  };

  testCodexDesktopIsSkippedByCiInstallSmokeTest = {
    expr = sets.wingetCiSkipInstall."9PLM9XGG6VKS" or false;
    expected = true;
  };
}
