{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  packages = import ../mcp-packages.nix { inherit inputs pkgs; };
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
      packages = [
        packages.xurl
        packages.hermes-xapi
      ];
      file.".xurl".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/xurl";
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
          args = [
            "mcp"
            "gateway"
            "run"
            "--profile"
            "dotfiles"
          ];
          # Nix's CLI replaces Docker's standard system plugin search directories.
          env.DOCKER_CLI_PLUGIN_DIRS =
            "/usr/local/lib/docker/cli-plugins:/usr/local/libexec/docker/cli-plugins:/usr/lib/docker/cli-plugins:/usr/libexec/docker/cli-plugins"
            + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ":/Applications/Docker.app/Contents/Resources/cli-plugins";
          startup_timeout_sec = 30;
        };
        pipedream = {
          url = "https://mcp.pipedream.net/v2";
          auth = "oauth";
        };
      };
  };
}
