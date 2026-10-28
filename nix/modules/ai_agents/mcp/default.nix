{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  packages = import ../mcp-packages.nix { inherit inputs pkgs; };
  dockerConfig =
    config.home.sessionVariables.DOCKER_CONFIG or (throw "Docker MCP requires DOCKER_CONFIG");
  dockerConfigDirectory =
    assert lib.assertMsg (dockerConfig != "") "Docker MCP requires a non-empty DOCKER_CONFIG";
    lib.removePrefix "${config.home.homeDirectory}/" dockerConfig;
  hermesHome = config.home.sessionVariables.HERMES_HOME or "${config.home.homeDirectory}/.hermes";
  backends = {
    chrome = {
      port = 8765;
      command = lib.getExe packages.chrome-devtools-mcp;
      args = [
        "--executable-path=${
          lib.getExe (
            if config.programs.chromium.enable then
              config.programs.chromium.finalPackage
            else
              pkgs.google-chrome
          )
        }"
        "--user-data-dir=${hermesHome}/.browser"
        "--headless"
        "--no-usage-statistics"
      ];
      env = { };
    };
    xapi = {
      port = 8766;
      command = lib.getExe packages.hermes-xapi;
      args = [ "mcp" ];
      env = {
        HERMES_DATA_DIR = hermesHome;
        DOTFILES_HERMES_OP_EXECUTABLE = lib.getExe pkgs._1password-cli;
      };
    };
  };
  services = lib.mapAttrs' (
    name: backend:
    lib.nameValuePair "mcp-${name}" {
      command = [
        (lib.getExe packages.mcp-proxy)
        "--host"
        "127.0.0.1"
        "--port"
        (toString backend.port)
        "--pass-environment"
        "--"
        backend.command
      ]
      ++ backend.args;
      environment = {
        HOME = config.home.homeDirectory;
      }
      // backend.env;
    }
  ) backends;
in
{
  config = lib.mkIf config.programs.mcp.enable {
    home = {
      sessionVariables.DOCKER_CONFIG = "${config.home.homeDirectory}/.docker";
      packages = [
        packages.docker-mcp
        packages.xurl
        packages.hermes-xapi
      ];
      file.".xurl".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/xurl";
      file.".docker/cli-plugins/docker-mcp" = {
        target = "${dockerConfigDirectory}/cli-plugins/docker-mcp";
        source = lib.getExe packages.docker-mcp;
      };
      activation.prepareXurlDirectory =
        lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
          ''
            run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg "${hermesHome}/.xurl"}
          '';
    };

    # xurl fixes its credential path at ~/.xurl. Keep the existing private cache
    # behind an XDG configuration link; Home Manager refuses conflicting files.
    xdg.configFile.xurl.source = config.lib.file.mkOutOfStoreSymlink "${hermesHome}/.xurl";

    # Both clients share one browser profile and one in-memory OAuth token store.
    # Home Manager starts these services after installing their configuration links.
    systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mapAttrs (name: service: {
        Unit.Description = "Shared ${name} server";
        Service = {
          ExecStart = lib.escapeShellArgs service.command;
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") service.environment;
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      }) services
    );
    launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.mapAttrs (name: service: {
        enable = true;
        config = {
          ProgramArguments = service.command;
          EnvironmentVariables = service.environment;
          KeepAlive = true;
          RunAtLoad = true;
          ThrottleInterval = 10;
          ProcessType = "Background";
          StandardOutPath = "${hermesHome}/${name}.log";
          StandardErrorPath = "${hermesHome}/${name}.log";
        };
      }) services
    );

    programs.mcp.servers =
      lib.mapAttrs (_: backend: {
        url = "http://127.0.0.1:${toString backend.port}/mcp";
      }) backends
      // {
        MCP_DOCKER = {
          command = lib.getExe pkgs.docker-client;
          env.DOCKER_CONFIG = dockerConfig;
          args = [
            "mcp"
            "gateway"
            "run"
            "--servers"
            "context7,deepwiki,exa,firecrawl,github-official,obsidian,playwright,tavily"
          ];
          startup_timeout_sec = 30;
        };
        pipedream = {
          url = "https://mcp.pipedream.net/v2";
          auth = "oauth";
        };
      };
  };
}
