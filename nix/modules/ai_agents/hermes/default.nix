{
  config,
  options,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  secretReferences = config.dotfiles.onePassword.secrets.references;
in
{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  config = lib.mkMerge [
    {
      programs.hermes-agent = {
        enable = true;
        desktop.enable = true;
      };
      services.hermes-agent = {
        enable = true;
        gateway.enable = true;
      };
    }
    (lib.mkIf
      (
        pkgs.stdenv.hostPlatform.isLinux
        && config.submoduleSupport.enable
        && config.dotfiles.onePassword.enable
        && config.services.hermes-agent.enable
      )
      {
        services.hermes-agent.settings.secrets.onepassword.binary_path = "/run/wrappers/bin/op";
        systemd.user.services =
          lib.optionalAttrs config.services.hermes-agent.gateway.enable {
            hermes-agent.Service = {
              NoNewPrivileges = lib.mkForce false;
              PrivateTmp = lib.mkForce false;
            };
          }
          // lib.optionalAttrs (config.services.hermes-agent.backend.mode != "none") {
            hermes-backend.Service = {
              NoNewPrivileges = lib.mkForce false;
              PrivateTmp = lib.mkForce false;
            };
          };
      }
    )
    {
      services.hermes-agent = lib.mkIf config.services.hermes-agent.enable {
        extraPackages = [ pkgs._1password-cli ];
        extraPlugins = [ (inputs.hermes-lcm // { name = "hermes-lcm"; }) ];
        mcpServers = lib.mapAttrs (
          name: server:
          let
            normalized = lib.hm.mcp.transformMcpServer {
              inherit server;
              extraTransforms = lib.optional ((server.command or null) != null) (
                lib.hm.mcp.wrapEnvFilesCommand { inherit pkgs name; }
              );
            };
            serverOptions = builtins.removeAttrs (options.services.hermes-agent.mcpServers.type.getSubOptions
              [ ]
            ) [ "_module" ];
          in
          lib.intersectAttrs serverOptions normalized
          // lib.optionalAttrs (normalized ? command) {
            command = toString normalized.command;
          }
          // lib.optionalAttrs (normalized ? startup_timeout_sec) {
            connect_timeout = normalized.startup_timeout_sec;
          }
          // lib.optionalAttrs (normalized ? tool_timeout_sec) {
            timeout = normalized.tool_timeout_sec;
          }
        ) config.programs.mcp.servers;
        settings = {
          model = {
            provider = "openai-codex";
            default = "gpt-6.1-sol";
          };
          # Let the upstream boot-time guard decide whether profile multiplexing is safe.
          gateway.multiplex_profiles = null;
          context.engine = "lcm";
          plugins.enabled = [ "hermes-lcm" ];
          # Desktop uses the local gateway without a Discord connection.
          platforms.discord.enabled = false;
          secrets.onepassword = {
            enabled = true;
            account = config.dotfiles.onePassword.account;
            env = {
              GITHUB_TOKEN = secretReferences.githubToken;
              XAI_API_KEY = secretReferences.xaiApiKey;
            };
          };
        };
      };
    }
  ];
}
