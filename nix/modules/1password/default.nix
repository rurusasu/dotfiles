{
  config,
  lib,
  pkgs,
  platform,
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
    darwinAppPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/Applications/1Password.app";
      description = "Path to the managed macOS 1Password application bundle.";
    };
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
  config = lib.mkMerge [
    { dotfiles.onePassword.enable = true; }
    (lib.mkIf config.dotfiles.onePassword.enable {
      home = {
        sessionVariables =
          lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
            OP_BIOMETRIC_UNLOCK_ENABLED = "true";
          }
          // lib.optionalAttrs (platform == "wsl") {
            WSLENV = "OP_ACCOUNT/u";
            OP_ACCOUNT = config.dotfiles.onePassword.account;
          };
        packages = [
          pkgs._1password-cli
        ]
        ++ lib.optional (!pkgs.stdenv.hostPlatform.isDarwin) pkgs._1password-gui;
        activation.onepasswordApplicationRegistration = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
          lib.hm.dag.entryAfter [ "copyApps" ] ''
            if [[ -d ${lib.escapeShellArg config.dotfiles.onePassword.darwinAppPath} ]]; then
              run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
                -f ${lib.escapeShellArg config.dotfiles.onePassword.darwinAppPath}
            fi
          ''
        );
      };
      launchd.agents.onepassword-ssh-environment = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        enable = true;
        config = {
          ProgramArguments = [
            "/bin/launchctl"
            "setenv"
            "SSH_AUTH_SOCK"
            config.home.sessionVariables.SSH_AUTH_SOCK
          ];
          RunAtLoad = true;
        };
      };
    })
  ];
}
