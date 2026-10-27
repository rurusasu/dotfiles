{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.dotfiles.desktop.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    targets.darwin.defaults."com.apple.finder" = {
      NewWindowTarget = "PfHm";
      _FXShowPosixPathInTitle = true;
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = true;
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };
  };
}
