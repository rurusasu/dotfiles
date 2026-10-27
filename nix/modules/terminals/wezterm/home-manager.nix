{
  config,
  lib,
  pkgs,
  ...
}:
let
  appearance = import ../appearance.nix;
  shellIntegration = ''
    if [ "''${TERM_PROGRAM-}" = "WezTerm" ]; then
      source "${config.programs.wezterm.package}/etc/profile.d/wezterm.sh"
    fi
  '';
in
{
  config = lib.mkIf config.programs.wezterm.enable {
    programs = {
      wezterm = {
        package = pkgs.wezterm;
        settings = {
          color_scheme = appearance.theme;
          font = lib.generators.mkLuaInline "wezterm.font(${builtins.toJSON appearance.font_family})";
          inherit (appearance) font_size;
        };
        extraConfig =
          lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            local dotfiles_terminfo_directory = ${
              lib.generators.toLua { } "${config.programs.wezterm.package.terminfo}/share/terminfo"
            }
          ''
          + builtins.readFile ./wezterm.lua;
        # The upstream integration installs prompt/OSC hooks in every terminal.
        # Scope it to WezTerm so Ghostty can use its own shell integration.
        enableBashIntegration = false;
        enableZshIntegration = false;
      };
      bash.initExtra = lib.mkIf config.programs.bash.enable shellIntegration;
      zsh.initContent = lib.mkIf config.programs.zsh.enable (lib.mkOrder 1000 shellIntegration);
    };
  };
}
