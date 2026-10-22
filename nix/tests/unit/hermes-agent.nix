{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  repositoryLock = builtins.fromJSON (builtins.readFile ../../../flake.lock);
  upstreamLock = builtins.fromJSON (builtins.readFile "${inputs.hermes-agent}/flake.lock");
  hermesNode =
    repositoryLock.nodes.${repositoryLock.nodes.${repositoryLock.root}.inputs.hermes-agent};
  upstreamInputs = upstreamLock.nodes.${upstreamLock.root}.inputs;

  mkTestHome =
    {
      system,
      homeDirectory,
    }:
    let
      pkgs = fixtures.mkPkgs system;
      testPackage =
        pkgs.runCommand "hermes-agent-test-package"
          {
            pname = "hermes-agent";
            version = "test";
            passthru.hermesDesktop = inputs.hermes-agent.packages.${system}.desktop;
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
      };
      modules = [
        {
          home = {
            username = "test-user";
            inherit homeDirectory;
            stateVersion = "25.05";
          };
          # The upstream module closes over inputs.self for its package
          # default. Pin its supported package option here so evaluation uses
          # this local derivation without forcing the upstream Python package.
          services.hermes-agent.package = testPackage;
        }
        ../../home/common.nix
        ../../modules/editors/nvim
      ];
    })
    // {
      inherit testPackage;
    };

  linux = mkTestHome {
    system = "x86_64-linux";
    homeDirectory = "/home/test-user";
  };
  darwin = mkTestHome {
    system = "aarch64-darwin";
    homeDirectory = "/Users/test-user";
  };
  darwinHost = fixtures.darwin.config;
  darwinHostHome = darwinHost.home-manager.users.test-user;

  hasPackage = needle: packages: builtins.any (item: item.drvPath == needle.drvPath) packages;
  hasHermesBootstrap =
    home: builtins.any (item: (item.pname or item.name) == "hermes-bootstrap") home;
  hasNodejs = home: builtins.any (item: (item.pname or item.name) == "nodejs") home;
in
{
  testHermesRuntimeUsesOfficialDependencyPins = {
    expr = builtins.all (
      name:
      let
        binding = hermesNode.inputs.${name};
        upstreamNode = upstreamLock.nodes.${upstreamInputs.${name}};
        expectedEdges = builtins.mapAttrs (
          _: edge: if builtins.isList edge then [ "hermes-agent" ] ++ edge else hermesNode.inputs.${edge}
        ) (upstreamNode.inputs or { });
      in
      builtins.isString binding
      && repositoryLock.nodes.${binding}.locked == upstreamNode.locked
      && repositoryLock.nodes.${binding}.original == upstreamNode.original
      && (repositoryLock.nodes.${binding}.inputs or { }) == expectedEdges
    ) (builtins.attrNames upstreamInputs);
    expected = true;
  };

  testHermesServicesPreserveTheOfficialRuntimeDependencies = {
    expr = {
      linuxPythonPackages = linux.config.services.hermes-agent.extraPythonPackages;
      linuxDependencyGroups = linux.config.services.hermes-agent.extraDependencyGroups;
      darwinPythonPackages = darwin.config.services.hermes-agent.extraPythonPackages;
      darwinDependencyGroups = darwin.config.services.hermes-agent.extraDependencyGroups;
    };
    expected = {
      linuxPythonPackages = [ ];
      linuxDependencyGroups = [ ];
      darwinPythonPackages = [ ];
      darwinDependencyGroups = [ ];
    };
  };

  testLinuxHermesUsesInjectedPackageAndSystemdContract = {
    expr = {
      package = hasPackage linux.testPackage linux.config.home.packages;
      home = linux.config.home.sessionVariables.HERMES_HOME;
      multiplexProfiles = linux.config.services.hermes-agent.settings.gateway.multiplex_profiles;
      serviceUsesInjectedPackage = builtins.any (
        command: inputs.nixpkgs.lib.hasPrefix "${linux.testPackage}/bin/hermes" command
      ) (inputs.nixpkgs.lib.toList linux.config.systemd.user.services.hermes-agent.Service.ExecStart);
    };
    expected = {
      package = true;
      home = "/home/test-user/.hermes";
      multiplexProfiles = true;
      serviceUsesInjectedPackage = true;
    };
  };

  testNativeBootstrapIsNixManagedAndTargetsHermesHome = {
    expr = {
      installed = hasHermesBootstrap linux.config.home.packages;
      nodeRuntimeInstalled = hasNodejs linux.config.home.packages;
      availableToGateway = hasHermesBootstrap linux.config.services.hermes-agent.extraPackages;
      nodeRuntimeInServiceExtraPackages = hasNodejs linux.config.services.hermes-agent.extraPackages;
      profileSyncWrapper = builtins.hasAttr "scripts/profile_sync.sh" linux.config.services.hermes-agent.hermesHomeFiles;
      profileSyncActivation = builtins.hasAttr "hermesProfileSyncWrapperExecutable" linux.config.home.activation;
      plugins = map (plugin: plugin.name) linux.config.services.hermes-agent.extraPlugins;
      manifest = import ../../modules/ai_agents/hermes/manifest.nix {
        hermesHome = "/home/test-user/.hermes";
      };
    };
    expected = {
      installed = true;
      nodeRuntimeInstalled = true;
      availableToGateway = true;
      nodeRuntimeInServiceExtraPackages = false;
      profileSyncWrapper = true;
      profileSyncActivation = true;
      plugins = [ "hermes-lcm" ];
      manifest = builtins.replaceStrings [ "/opt/data" ] [ "/home/test-user/.hermes" ] (
        builtins.readFile ../../modules/ai_agents/hermes/manifest.yaml
      );
    };
  };

  testDarwinHermesLaunchAgentUsesInjectedPackage = {
    expr = builtins.elem "${darwin.testPackage}/bin/hermes" darwin.config.launchd.agents.hermes-agent.config.ProgramArguments;
    expected = true;
  };

  testDarwinHermesUsesOfficialBundleForCliGatewayAndSystemGui = {
    expr =
      let
        package = darwinHostHome.services.hermes-agent.package;
      in
      {
        packageName = package.pname or null;
        version = package.version or null;
        sourceUrl = if package ? src && builtins.isAttrs package.src then package.src.url or null else null;
        cliUsesGatewayPackage = darwinHostHome.programs.hermes-agent.package.drvPath == package.drvPath;
        cliInstalled = hasPackage package darwinHostHome.home.packages;
        gatewayUsesSelectedPackage = builtins.elem "${package}/bin/hermes" darwinHostHome.launchd.agents.hermes-agent.config.ProgramArguments;
        systemGuiUsesGatewayPackage = hasPackage package darwinHost.environment.systemPackages;
      };
    expected = {
      packageName = "hermes-agent-bundled";
      version = "0.22.0";
      sourceUrl = "https://hermes-assets.nousresearch.com/releases/tag/rc.3-v0.22.0/HermesBundled-0.22.0-mac-arm64.zip";
      cliUsesGatewayPackage = true;
      cliInstalled = true;
      gatewayUsesSelectedPackage = true;
      systemGuiUsesGatewayPackage = true;
    };
  };

  testLinuxHermesDesktopIsInstalledByHomeManager = {
    expr = {
      enabled = linux.config.programs.hermes-agent.desktop.enable;
      installed = builtins.any (
        package: (package.pname or "") == "hermes-desktop"
      ) linux.config.home.packages;
    };
    expected = {
      enabled = true;
      installed = true;
    };
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
      enabled = darwin.config.launchd.agents.hermes-agent.enable;
      homeVariable = darwin.config.launchd.agents.hermes-agent.config.EnvironmentVariables.HERMES_HOME;
      runAtLoad = darwin.config.launchd.agents.hermes-agent.config.RunAtLoad;
      keepAlive = darwin.config.launchd.agents.hermes-agent.config.KeepAlive;
    };
    expected = {
      home = "/Users/test-user/.hermes";
      enabled = true;
      homeVariable = "/Users/test-user/.hermes";
      runAtLoad = true;
      keepAlive = true;
    };
  };
}
