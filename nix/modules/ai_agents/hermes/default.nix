{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  programs.hermes-agent = {
    enable = true;
    desktop.enable = true;
  };

  services.hermes-agent = {
    enable = true;
    package = lib.mkDefault (
      import ./package.nix {
        inherit pkgs;
        source = inputs.hermes-agent;
        package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
      }
    );
    gateway.enable = true;
    extraPackages = [ pkgs._1password-cli ];
    extraPlugins = [ (inputs.hermes-lcm // { name = "hermes-lcm"; }) ];
    mcpServers = lib.mapAttrs (
      _: server:
      let
        normalized = lib.hm.mcp.transformMcpServer { inherit server; };
      in
      lib.filterAttrs (
        name: _:
        builtins.elem name [
          "command"
          "args"
          "env"
          "url"
          "headers"
          "auth"
          "enabled"
          "timeout"
          "connect_timeout"
          "tools"
          "sampling"
        ]
      ) normalized
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
      # Null also replaces the old explicit true in the mutable config, so the
      # upstream boot-time guard decides whether profile multiplexing is safe.
      gateway.multiplex_profiles = null;
      context.engine = "lcm";
      plugins.enabled = [ "hermes-lcm" ];
      platforms.discord.allow_bots = "mentions";
      secrets.onepassword = {
        enabled = true;
        account = config.dotfiles.onePassword.account;
        env = {
          GITHUB_TOKEN = "op://openclaw/GitHubUsedOpenClawPAT/credential";
          XAI_API_KEY = "op://openclaw/xAI-Grok-Twitter/console/apikey";
          DISCORD_BOT_TOKEN = "op://openclaw/Master/Discord/bot_token";
          DISCORD_ALLOWED_USERS = "op://openclaw/Master/Discord/allowed_users";
        };
      };
    };
  };
}
