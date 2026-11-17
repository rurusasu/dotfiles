{ homeConfigurations }:
let
  inherit (homeConfigurations) darwin;
  disabled = darwin.extendModules {
    modules = [
      ({ lib, ... }: { services.silverbullet-trial.enable = lib.mkForce false; })
    ];
  };
  state = home: {
    agent = home.config.launchd.agents.silverbullet-trial.enable or false;
    directory = home.config.home.activation ? silverbulletTrialDirectory;
  };
in
{
  testSilverbulletTrialIsDarwinOnlyAndCanBeDisabled = {
    expr = map state [
      darwin
      disabled
      homeConfigurations.linux
    ];
    expected = [
      {
        agent = true;
        directory = true;
      }
      {
        agent = false;
        directory = false;
      }
      {
        agent = false;
        directory = false;
      }
    ];
  };
}
