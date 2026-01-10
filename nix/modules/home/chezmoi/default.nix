# Chezmoi module for Home Manager
# Manages dotfiles with OS-independent configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.chezmoi;
in
{
  options.programs.chezmoi = {
    enable = lib.mkEnableOption "chezmoi dotfile manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.chezmoi;
      description = "The chezmoi package to use";
    };

    sourceDir = lib.mkOption {
      type = lib.types.str;
      default = "~/.local/share/chezmoi";
      description = "Path to chezmoi source directory";
    };

    onePassword = {
      enable = lib.mkEnableOption "1Password SSH agent integration";

      agentPath = lib.mkOption {
        type = lib.types.str;
        default =
          if pkgs.stdenv.isDarwin then
            "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
          else
            "~/.1password/agent.sock";
        description = "Path to 1Password SSH agent socket";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Create 1Password agent symlink for Linux/WSL
    home.file = lib.mkIf (cfg.onePassword.enable && pkgs.stdenv.isLinux) {
      ".1password/agent.sock".source = config.lib.file.mkOutOfStoreSymlink
        "/mnt/c/Users/${config.home.username}/.1password/agent.sock";
    };

    # SSH config for 1Password integration
    programs.ssh = lib.mkIf cfg.onePassword.enable {
      enable = true;
      extraConfig = ''
        Host *
            IdentityAgent "${cfg.onePassword.agentPath}"
      '';
    };
  };
}
