{ inputs }:
let
  mkHome =
    {
      system,
      installFeatures ? [ ],
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs system;
      extraSpecialArgs = {
        inherit inputs installFeatures;
      };
      modules = [
        {
          home.username = "test-user";
          home.homeDirectory = if system == "aarch64-darwin" then "/Users/test-user" else "/home/test-user";
        }
        ../home/hermes-agent.nix
      ];
    };

  linux = mkHome {
    system = "x86_64-linux";
    installFeatures = [ "WithHermes" ];
  };
  darwin = mkHome {
    system = "aarch64-darwin";
    installFeatures = [ "WithHermes" ];
  };
  disabled = mkHome { system = "x86_64-linux"; };

  package = system: inputs.hermes-agent.packages.${system}.default;
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
      package = hasPackage (package "x86_64-linux") disabled.config.home.packages;
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

  testLinuxHermesUsesLockedPackageAndExistingStatePath = {
    expr = {
      package = hasPackage (package "x86_64-linux") linux.config.home.packages;
      home = linux.config.home.sessionVariables.HERMES_HOME;
      featureFlag = linux.config.home.sessionVariables.DOTFILES_WITH_HERMES;
      executable = linux.config.systemd.user.services.hermes-agent.Service.ExecStart;
      workingDirectory = linux.config.systemd.user.services.hermes-agent.Service.WorkingDirectory;
      restart = linux.config.systemd.user.services.hermes-agent.Service.Restart;
      wantedBy = linux.config.systemd.user.services.hermes-agent.Install.WantedBy;
    };
    expected = {
      package = true;
      home = "/home/test-user/.hermes";
      featureFlag = "1";
      executable = "${package "x86_64-linux"}/bin/hermes gateway run";
      workingDirectory = "/home/test-user";
      restart = "on-failure";
      wantedBy = [ "default.target" ];
    };
  };

  testDarwinHermesUsesLaunchdAndExistingStatePath = {
    expr = {
      package = hasPackage (package "aarch64-darwin") darwin.config.home.packages;
      home = darwin.config.home.sessionVariables.HERMES_HOME;
      featureFlag = darwin.config.home.sessionVariables.DOTFILES_WITH_HERMES;
      enabled = darwin.config.launchd.agents.hermes-agent.enable;
      arguments = darwin.config.launchd.agents.hermes-agent.config.ProgramArguments;
      homeVariable = darwin.config.launchd.agents.hermes-agent.config.EnvironmentVariables.HERMES_HOME;
      runAtLoad = darwin.config.launchd.agents.hermes-agent.config.RunAtLoad;
      keepAlive = darwin.config.launchd.agents.hermes-agent.config.KeepAlive;
    };
    expected = {
      package = true;
      home = "/Users/test-user/.hermes";
      featureFlag = "1";
      enabled = true;
      arguments = [ "${package "aarch64-darwin"}/bin/hermes" "gateway" "run" ];
      homeVariable = "/Users/test-user/.hermes";
      runAtLoad = true;
      keepAlive = true;
    };
  };
}
