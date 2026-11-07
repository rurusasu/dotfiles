{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lifelog;
in
{
  options.programs.lifelog = {
    enable = lib.mkEnableOption "Lifelog local workspace";
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./package.nix { inherit pkgs; };
      description = "Lifelog package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    # The local bin directory precedes the Nix profile in this WSL setup.
    home.file.".local/bin/lifelog".source = "${cfg.package}/bin/lifelog";
    xdg.desktopEntries.lifelog = {
      name = "Lifelog";
      genericName = "Local file workspace";
      exec = "${cfg.package}/bin/lifelog";
      categories = [
        "Office"
        "Utility"
      ];
      terminal = false;
    };
  };
}
