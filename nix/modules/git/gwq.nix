{
  config,
  lib,
  pkgs,
  ...
}:
let
  format = pkgs.formats.toml { };
  executable = lib.getExe pkgs.gwq;
in
{
  options.dotfiles.gwq.settings = lib.mkOption {
    inherit (format) type;
    default = { };
    description = "Declarative gwq configuration, with host-specific worktree locations.";
  };

  config = {
    home.packages = [ pkgs.gwq ];
    dotfiles.gwq.settings = {
      worktree = {
        basedir = lib.mkDefault "${config.home.homeDirectory}/worktrees";
        auto_mkdir = lib.mkDefault true;
      };
      cd.launch_shell = lib.mkDefault false;
    };

    xdg.configFile."gwq/config.toml".source =
      format.generate "gwq-config.toml" config.dotfiles.gwq.settings;

    programs = {
      git.settings.alias.gtr = "!gwq add";
      # Completion also provides the wrapper used by `gwq cd` in the current shell.
      bash.initExtra = ''
        source <(${executable} completion bash)
      '';
      zsh.initContent = ''
        source <(${executable} completion zsh)
      '';
    };
  };
}
