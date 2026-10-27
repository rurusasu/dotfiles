{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.ghq.enable = lib.mkEnableOption "ghq repository management";

  config = lib.mkIf config.programs.ghq.enable {
    home.packages = [ pkgs.ghq ];
    programs.git.settings.ghq.root = lib.mkDefault "~/ghq";
  };
}
