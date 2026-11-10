{
  config,
  lib,
  pkgs,
  ...
}:
let
  secretReference =
    default:
    lib.mkOption {
      type = lib.types.strMatching "op://[^\r\n]+";
      inherit default;
      description = "1Password secret reference resolved at runtime.";
    };
in
{
  options.dotfiles.onePassword = {
    enable = lib.mkEnableOption "1Password CLI and desktop SSH integration";
    account = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
      example = "my.1password.com";
      description = "1Password account used by host integrations.";
    };
    secrets = {
      references = {
        githubToken = secretReference "op://openclaw/GitHubUsedOpenClawPAT/credential";
        xaiApiKey = secretReference "op://openclaw/xAI-Grok-Twitter/console/apikey";
        discordBotToken = secretReference "op://openclaw/Master/Discord/bot_token";
        discordAllowedUsers = secretReference "op://openclaw/Master/Discord/allowed_users";
        exaApiKey = secretReference "op://openclaw/ExaUsedOpenclawPAT/credential";
        firecrawlApiKey = secretReference "op://openclaw/FirecrawlUsedOpenclawPAT/credential";
        tavilyApiToken = secretReference "op://openclaw/TavilyUsedOpenclawPAT/credential";
        serviceAccountToken = secretReference "op://openclaw/3bgd5qtytxuvuauauyqr2p4iki/credential";
      };
      xapi = {
        vault = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "openclaw";
          description = "1Password vault containing the X API OAuth item.";
        };
        item = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "Hermes X API MCP";
          description = "1Password item containing the X API OAuth credentials.";
        };
      };
    };
  };
  config = lib.mkIf config.dotfiles.onePassword.enable {
    home.packages = [
      pkgs._1password-cli
      pkgs._1password-gui
    ];
  };
}
