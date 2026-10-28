{
  inputs,
  fixtures,
  code,
  files,
  upstream,
}:
let
  repositoryLock = builtins.fromJSON (builtins.readFile files."flake.lock");
  upstreamLock = builtins.fromJSON (builtins.readFile upstream.hermes-agent.files."flake.lock");
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
    (fixtures.mkHome system [
      {
        home.homeDirectory = homeDirectory;
        # The upstream module closes over inputs.self for its package
        # default. Pin its supported package option here so evaluation uses
        # this local derivation without forcing the upstream Python package.
        programs.hermes-agent = {
          enable = true;
          desktop.enable = true;
        };
        services.hermes-agent = {
          enable = true;
          gateway.enable = true;
          package = testPackage;
        };
        programs.mcp.enable = true;
      }
      (fixtures.homeModule "common")
    ])
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

  hasNodejs = home: builtins.any (item: (item.pname or item.name) == "nodejs") home;
  upstreamPackage = inputs.hermes-agent.packages.x86_64-linux.default;
  # Model each input version explicitly; upstream may publish a placeholder
  # today and a release number tomorrow. Keep its actual runtime in both cases.
  packageWithVersion =
    version:
    upstreamPackage.overrideAttrs (previous: {
      inherit version;
      passthru = previous.passthru // {
        hermesDesktop = previous.passthru.hermesDesktop.overrideAttrs { inherit version; };
      };
    });
  knownReleasePackage = packageWithVersion "0.21.4";
  versionPackage =
    kind: package:
    let
      source = inputs.hermes-agent // {
        outPath = files.nix.tests.fixtures.hermes-version.${kind}.__path;
        rev = "0123456789abcdef0123456789abcdef01234567";
        lastModifiedDate = "20261026122553";
      };
    in
    code.nix.modules.ai_agents.hermes.package {
      inherit package source;
      pkgs = fixtures.mkPkgs "x86_64-linux";
    };
in
{
  testHermesVersionMetadataPreservesKnownReleaseAndRuntime = {
    expr = {
      inherit (versionPackage "legacy" knownReleasePackage) version;
      samePackage = (versionPackage "legacy" knownReleasePackage).drvPath == knownReleasePackage.drvPath;
      sameRuntime =
        (versionPackage "legacy" knownReleasePackage).hermesVenv.drvPath
        == knownReleasePackage.hermesVenv.drvPath;
      knownDesktopPreserved =
        (versionPackage "legacy" knownReleasePackage).hermesDesktop.drvPath
        == knownReleasePackage.hermesDesktop.drvPath;
    };
    expected = {
      version = "0.21.4";
      samePackage = true;
      sameRuntime = true;
      knownDesktopPreserved = true;
    };
  };

  testHermesKnownSourceVersionRepairsPlaceholderMetadata = {
    expr =
      let
        package = packageWithVersion "0.0.0";
        corrected = versionPackage "legacy" package;
      in
      {
        inherit (corrected) version;
        desktopVersion = corrected.hermesDesktop.version;
        samePackage = corrected.drvPath == package.drvPath;
        sameRuntime = corrected.hermesVenv.drvPath == package.hermesVenv.drvPath;
      };
    expected = {
      version = "0.21.4";
      desktopVersion = "0.21.4";
      samePackage = false;
      sameRuntime = true;
    };
  };

  testHermesDevelopmentVersionIdentifiesDateAndRevision = {
    expr = (versionPackage "stamped" (packageWithVersion "0.0.0")).version;
    expected = "unstable-2026-10-26-01234567";
  };

  testHermesStaticPlaceholderIsNotAReleaseVersion = {
    expr = (versionPackage "placeholder" (packageWithVersion "0.0.0")).version;
    expected = "unstable-2026-10-26-01234567";
  };

  testHermesVersionCorrectionFollowsRuntimeOverrides = {
    expr =
      let
        original = versionPackage "stamped" (packageWithVersion "0.0.0");
        customized = original.override { extraDependencyGroups = [ "dev" ]; };
      in
      {
        changedRuntime = customized.hermesVenv.drvPath != original.hermesVenv.drvPath;
        followsRuntime = inputs.nixpkgs.lib.hasInfix (builtins.unsafeDiscardStringContext "${customized.hermesVenv}/bin/hermes") customized.postInstall;
        staleRuntime = inputs.nixpkgs.lib.hasInfix (builtins.unsafeDiscardStringContext "${original.hermesVenv}/bin/hermes") customized.postInstall;
      };
    expected = {
      changedRuntime = true;
      followsRuntime = true;
      staleRuntime = false;
    };
  };

  testHermesRuntimeUsesOfficialDependencyPins = {
    expr = builtins.all (
      name:
      let
        binding = hermesNode.inputs.${name};
        upstreamNode = upstreamLock.nodes.${upstreamInputs.${name}};
      in
      builtins.isString binding
      && repositoryLock.nodes.${binding}.locked == upstreamNode.locked
      && repositoryLock.nodes.${binding}.original == upstreamNode.original
      &&
        (repositoryLock.nodes.${binding}.inputs or { }) == builtins.mapAttrs (
          _: edge: if builtins.isList edge then [ "hermes-agent" ] ++ edge else hermesNode.inputs.${edge}
        ) (upstreamNode.inputs or { })
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
      package =
        (needle: packages: builtins.any (item: item.drvPath == needle.drvPath) packages) linux.testPackage
          linux.config.home.packages;
      home = linux.config.home.sessionVariables.HERMES_HOME;
      multiplexProfiles = linux.config.services.hermes-agent.settings.gateway.multiplex_profiles;
      model = linux.config.services.hermes-agent.settings.model or { };
      serviceUsesInjectedPackage = builtins.any (
        command: inputs.nixpkgs.lib.hasPrefix "${linux.testPackage}/bin/hermes" command
      ) (inputs.nixpkgs.lib.toList linux.config.systemd.user.services.hermes-agent.Service.ExecStart);
    };
    expected = {
      package = true;
      home = "/home/test-user/.hermes";
      multiplexProfiles = null;
      model = {
        provider = "openai-codex";
        default = "gpt-6.1-sol";
      };
      serviceUsesInjectedPackage = true;
    };
  };

  testHermesSharedMcpTransportsReachFinalConfiguration = {
    expr =
      let
        servers = linux.config.services.hermes-agent.settings.mcp_servers;
      in
      {
        chrome = servers.chrome.url;
        xapi = servers.xapi.url;
        pipedream = { inherit (servers.pipedream) url auth; };
        localCommands = builtins.filter (name: servers.${name} ? command) [
          "chrome"
          "xapi"
          "pipedream"
        ];
      };
    expected = {
      chrome = "http://127.0.0.1:8765/mcp";
      xapi = "http://127.0.0.1:8766/mcp";
      pipedream = {
        url = "https://mcp.pipedream.net/v2";
        auth = "oauth";
      };
      localCommands = [ ];
    };
  };

  testHermesRuntimeAndPluginsAreConfigured = {
    expr = {
      nodeRuntimeInstalled = hasNodejs linux.config.home.packages;
      nodeRuntimeInServiceExtraPackages = hasNodejs linux.config.services.hermes-agent.extraPackages;
      mcpServers = builtins.attrNames linux.config.services.hermes-agent.mcpServers;
      plugins = map (plugin: plugin.name) linux.config.services.hermes-agent.extraPlugins;
    };
    expected = {
      nodeRuntimeInstalled = false;
      nodeRuntimeInServiceExtraPackages = false;
      mcpServers = [
        "MCP_DOCKER"
        "chrome"
        "pipedream"
        "xapi"
      ];
      plugins = [ "hermes-lcm" ];
    };
  };

  testDarwinHermesLaunchAgentUsesInjectedPackage = {
    expr = builtins.elem "${darwin.testPackage}/bin/hermes" darwin.config.launchd.agents.hermes-agent.config.ProgramArguments;
    expected = true;
  };

  testHermesDesktopIsInstalledByHomeManagerAcrossPlatforms = {
    expr =
      map
        (home: {
          enabled = home.config.programs.hermes-agent.desktop.enable;
          installed = builtins.any (
            package: (package.pname or "") == "hermes-desktop"
          ) home.config.home.packages;
        })
        [
          linux
          darwin
        ];
    expected = [
      {
        enabled = true;
        installed = true;
      }
      {
        enabled = true;
        installed = true;
      }
    ];
  };

  testDarwinHermesLaunchAgentTargetsGateway = {
    expr = builtins.elem "gateway" darwin.config.launchd.agents.hermes-agent.config.ProgramArguments;
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
