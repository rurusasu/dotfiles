# SSH module with 1Password integration
# OS-independent SSH configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.ssh;

  # Determine 1Password agent path based on OS
  defaultAgentPath =
    if pkgs.stdenv.isDarwin then
      "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else if pkgs.stdenv.isLinux then
      "~/.1password/agent.sock"
    else
      # Windows path (for reference, typically handled by chezmoi)
      "//./pipe/openssh-ssh-agent";
in
{
  options.modules.ssh = {
    enable = lib.mkEnableOption "SSH configuration";

    onePassword = {
      enable = lib.mkEnableOption "1Password SSH agent integration";

      agentPath = lib.mkOption {
        type = lib.types.str;
        default = defaultAgentPath;
        description = "Path to 1Password SSH agent socket";
      };
    };

    githubHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          hostname = lib.mkOption {
            type = lib.types.str;
            default = "github.com";
            description = "GitHub hostname";
          };
          identityFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to SSH public key";
          };
          identitiesOnly = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Only use specified identity";
          };
        };
      });
      default = { };
      description = "GitHub host configurations";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ssh = {
      enable = true;

      extraConfig = lib.mkIf cfg.onePassword.enable ''
        Host *
            IdentityAgent "${cfg.onePassword.agentPath}"
      '';

      matchBlocks = lib.mapAttrs (name: hostCfg: {
        hostname = hostCfg.hostname;
        user = "git";
        identityFile = hostCfg.identityFile;
        identitiesOnly = hostCfg.identitiesOnly;
      }) cfg.githubHosts;
    };
  };
}
