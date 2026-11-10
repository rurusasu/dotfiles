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

  config = lib.mkMerge [
    { programs.ghq.enable = true; }
    (lib.mkIf config.programs.ghq.enable {
      home.packages = [ pkgs.ghq ];
      home.sessionVariables.GHQ_ROOT = config.programs.ghq.root;
    })
  ];
}
