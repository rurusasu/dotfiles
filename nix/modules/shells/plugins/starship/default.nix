{ config, lib, ... }:
let
  cfg = config.dotfiles.starship;
  osStyle = "bold white";
  osPrefix = if cfg.osSymbol == null then "$os" else "[${cfg.osSymbol}](${osStyle}) ";
in
{
  options.dotfiles.starship.osSymbol = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "❄️ ";
    description = ''
      Static OS symbol selected by the host. When null, Starship detects the OS
      at runtime instead.
    '';
  };

  config = {
    # Replace the previously deployed TOML when Home Manager takes ownership.
    home.file = lib.mkIf config.programs.starship.enable {
      ${config.programs.starship.configPath}.force = true;
    };

    programs.starship = {
      enableZshIntegration = true;
      # The preserved Bash configuration initializes Starship once.
      enableBashIntegration = false;

      settings = {
        add_newline = true;
        scan_timeout = 500;
        format =
          osPrefix + "$username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";

        character = {
          success_symbol = "[>](bold green)";
          error_symbol = "[x](bold red)";
        };

        os = {
          disabled = cfg.osSymbol != null;
          format = "[$symbol]($style) ";
          style = osStyle;
        };

        username = {
          show_always = true;
          format = "[$user]($style)";
        };

        hostname = {
          ssh_only = false;
          format = "@[$hostname]($style) ";
        };

        memory_usage = {
          disabled = false;
          threshold = 0;
          format = "[$ram]($style) ";
        };

        directory = {
          truncation_length = 3;
          truncate_to_repo = true;
        };

        git_branch = {
          symbol = " ";
          format = "on [$symbol$branch]($style) ";
        };

        git_status = {
          ahead = "";
          behind = "";
          diverged = "";
        };

        nix_shell = {
          symbol = " ";
          format = "[$symbol$state]($style) ";
        };
      };
    };
  };
}
