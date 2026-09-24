{ inputs }:
let
  fixtures = import ../test-fixtures.nix { inherit inputs; };

  mkTestHome =
    {
      system,
      homeDirectory,
      installFeatures ? [ ],
    }:
    let
      pkgs = fixtures.mkPkgs system;
      testPackage =
        pkgs.runCommand "hermes-agent-test-package"
          {
            pname = "hermes-agent";
            version = "test";
          }
          ''
            mkdir -p "$out/bin"
            touch "$out/bin/hermes"
          '';
    in
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        inherit installFeatures;
      };
      modules = [
        {
          home.username = "test-user";
          home.homeDirectory = homeDirectory;
          home.stateVersion = "25.05";
          # The upstream module closes over inputs.self for its package
          # default. Pin its supported package option here so evaluation uses
          # this local derivation without forcing the upstream Python package.
          services.hermes-agent.package = testPackage;
        }
        ../home/hermes-agent.nix
      ];
    })
    // {
      inherit testPackage;
    };

  linux = mkTestHome {
    system = "x86_64-linux";
    homeDirectory = "/home/test-user";
    installFeatures = [ "WithHermes" ];
  };
  darwin = mkTestHome {
    system = "aarch64-darwin";
    homeDirectory = "/Users/test-user";
    installFeatures = [ "WithHermes" ];
  };
  disabled = mkTestHome {
    system = "x86_64-linux";
    homeDirectory = "/home/test-user";
  };

  hasPackage = needle: packages: builtins.any (item: item.drvPath == needle.drvPath) packages;
in
{
  testHermesFeatureDoesNotEnableDockerOrOllama = {
    expr = import ../flakes/lib/install-features.nix {
      lib = inputs.nixpkgs.lib;
      withHermes = true;
    };
    expected = [ "WithHermes" ];
  };

  testHermesIsAbsentWithoutTheInstallFeature = {
    expr = {
      package = hasPackage disabled.testPackage disabled.config.home.packages;
      sessionVariable = builtins.hasAttr "HERMES_HOME" disabled.config.home.sessionVariables;
      featureFlag = disabled.config.home.sessionVariables.DOTFILES_WITH_HERMES;
      systemdService = builtins.hasAttr "hermes-agent" disabled.config.systemd.user.services;
    };
    expected = {
      package = false;
      sessionVariable = false;
      featureFlag = "0";
      systemdService = false;
    };
  };

  testLinuxHermesUsesInjectedPackageAndSystemdContract = {
    expr = {
      package = hasPackage linux.testPackage linux.config.home.packages;
      home = linux.config.home.sessionVariables.HERMES_HOME;
      featureFlag = linux.config.home.sessionVariables.DOTFILES_WITH_HERMES;
      serviceUsesInjectedPackage = builtins.any (
        command: inputs.nixpkgs.lib.hasPrefix "${linux.testPackage}/bin/hermes" command
      ) (inputs.nixpkgs.lib.toList linux.config.systemd.user.services.hermes-agent.Service.ExecStart);
    };
    expected = {
      package = true;
      home = "/home/test-user/.hermes";
      featureFlag = "1";
      serviceUsesInjectedPackage = true;
    };
  };

  testDarwinHermesLaunchAgentUsesInjectedPackage = {
    expr = builtins.elem "${darwin.testPackage}/bin/hermes" (
      darwin.config.launchd.agents.hermes-agent.config.ProgramArguments
    );
    expected = true;
  };

  testDarwinHermesLaunchAgentTargetsGateway = {
    expr =
      let
        arguments = darwin.config.launchd.agents.hermes-agent.config.ProgramArguments;
      in
      builtins.elem "gateway" arguments;
    expected = true;
  };

  testDarwinHermesLaunchAgentHomeAndLifecycle = {
    expr = {
      home = darwin.config.home.sessionVariables.HERMES_HOME;
      featureFlag = darwin.config.home.sessionVariables.DOTFILES_WITH_HERMES;
      enabled = darwin.config.launchd.agents.hermes-agent.enable;
      homeVariable = darwin.config.launchd.agents.hermes-agent.config.EnvironmentVariables.HERMES_HOME;
      runAtLoad = darwin.config.launchd.agents.hermes-agent.config.RunAtLoad;
      keepAlive = darwin.config.launchd.agents.hermes-agent.config.KeepAlive;
    };
    expected = {
      home = "/Users/test-user/.hermes";
      featureFlag = "1";
      enabled = true;
      homeVariable = "/Users/test-user/.hermes";
      runAtLoad = true;
      keepAlive = true;
    };
  };
}
