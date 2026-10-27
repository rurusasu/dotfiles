{ fixtures }:
let
  windows = fixtures.windowsPackages;
in
{
  testCodexDesktopUsesAppxLaunchTargetVerifier = {
    expr = windows."9PLM9XGG6VKS".verifyCommand;
    expected = {
      type = "appxLaunchTarget";
      command = "OpenAI.Codex";
      args = [ "OpenAI.Codex_2p2nqsd0c76g0!App" ];
    };
  };

  testCodexDesktopIsSkippedByCiInstallSmokeTest = {
    expr = windows."9PLM9XGG6VKS".ciSkipInstall or false;
    expected = true;
  };
}
