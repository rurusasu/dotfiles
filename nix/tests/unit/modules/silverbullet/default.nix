{ homeConfigurations }:
let
  inherit (homeConfigurations) darwin;
  disabled = darwin.extendModules {
    modules = [
      (
        { lib, ... }:
        {
          programs.silverbullet.enable = lib.mkForce false;
          services.silverbullet-trial.enable = lib.mkForce false;
        }
      )
    ];
  };
  state = home: {
    desktop = builtins.any (
      package: package.pname or "" == "silverbullet-desktop"
    ) home.config.home.packages;
    agent = home.config.launchd.agents.silverbullet-trial.enable or false;
    directory = home.config.home.activation ? silverbulletTrialDirectory;
    lifelog = home.config.home.file ? lifelog;
  };
in
{
  testSilverbulletIsDarwinOnlyAndCanBeDisabled = {
    expr = map state [
      darwin
      disabled
      homeConfigurations.linux
    ];
    expected = [
      {
        desktop = true;
        agent = true;
        directory = true;
        lifelog = true;
      }
      {
        desktop = false;
        agent = false;
        directory = false;
        lifelog = false;
      }
      {
        desktop = false;
        agent = false;
        directory = false;
        lifelog = false;
      }
    ];
  };
}
