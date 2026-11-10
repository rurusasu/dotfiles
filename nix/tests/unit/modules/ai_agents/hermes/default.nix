{
  inputs,
  fixtures,
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
        dotfiles.onePassword = {
          account = "fixture.1password.com";
          secrets.references.githubToken = "op://fixture/github/credential";
        };
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
in
{
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
      model = linux.config.services.hermes-agent.settings.model or { };
      secretAccount = linux.config.services.hermes-agent.settings.secrets.onepassword.account;
      githubReference = linux.config.services.hermes-agent.settings.secrets.onepassword.env.GITHUB_TOKEN;
      serviceUsesInjectedPackage = builtins.any (
        command: inputs.nixpkgs.lib.hasPrefix "${linux.testPackage}/bin/hermes" command
      ) (inputs.nixpkgs.lib.toList linux.config.systemd.user.services.hermes-agent.Service.ExecStart);
    };
    expected = {
      package = true;
      home = "/home/test-user/.hermes";
      model = {
        provider = "openai-codex";
        default = "gpt-6.1-sol";
      };
      secretAccount = "fixture.1password.com";
      githubReference = "op://fixture/github/credential";
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
