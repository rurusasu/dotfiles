{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.ghq = {
    enable = lib.mkEnableOption "ghq repository management";
    root = lib.mkOption {
      type = lib.types.str;
      default = config.home.homeDirectory + "/ghq";
      description = "Root directory for repositories managed by ghq.";
    };
  };

  config = lib.mkIf config.programs.ghq.enable {
    home.packages = [ pkgs.ghq ];
    programs.git.settings.ghq.root = config.programs.ghq.root;
  };
}
