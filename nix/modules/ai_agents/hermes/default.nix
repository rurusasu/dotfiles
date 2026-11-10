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

  config.services.hermes-agent = lib.mkIf config.services.hermes-agent.enable {
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
      platforms.discord.allow_bots = "mentions";
      secrets.onepassword = {
        enabled = true;
        account = config.dotfiles.onePassword.account;
        env = {
          GITHUB_TOKEN = secretReferences.githubToken;
          XAI_API_KEY = secretReferences.xaiApiKey;
          DISCORD_BOT_TOKEN = secretReferences.discordBotToken;
          DISCORD_ALLOWED_USERS = secretReferences.discordAllowedUsers;
        };
      };
    };
  };
}
