{
  config,
  lib,
  pkgs,
  ...
}:
let
  osSymbol =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "🍎 "
    else if pkgs.stdenv.hostPlatform.isLinux then
      "❄️ "
    else
      null;
  osStyle = "bold white";
in
{
  config = lib.mkIf config.programs.starship.enable {
    # Replace the previously deployed TOML when Home Manager takes ownership.
    home.file = lib.mkIf config.programs.starship.enable {
      ${config.programs.starship.configPath}.force = true;
    };

    programs.starship = {
      enableZshIntegration = true;
      enableBashIntegration = true;

      settings = {
        add_newline = true;
        scan_timeout = 500;
        format =
          (if osSymbol == null then "$os" else "[${osSymbol}](${osStyle}) ")
          + "$username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";

        character = {
          success_symbol = "[>](bold green)";
          error_symbol = "[x](bold red)";
        };

        os = {
          disabled = osSymbol != null;
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
