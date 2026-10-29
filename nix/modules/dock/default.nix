{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.dotfiles.desktop.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    targets.darwin.defaults."com.apple.dock" = {
      tilesize = 50;
      autohide = true;
      launchanim = true;
      show-process-indicators = true;
      show-recents = false;
      persistent-apps = [
        "${config.programs.chatgpt.package}/Applications/ChatGPT.app"
        "${config.programs.dia.package}/Applications/Dia.app"
        "${config.programs.ghostty.package}/Applications/Ghostty.app"
        "${pkgs.obsidian}/Applications/Obsidian.app"
      ]
      ++ lib.optional config.programs.strata.enable "${config.programs.strata.package}/Applications/Strata.app";
      persistent-others = [ ];
      showDesktopGestureEnabled = true;
      showMissionControlGestureEnabled = true;
      showAppExposeGestureEnabled = false;
      showLaunchpadGestureEnabled = false;
    };
  };
}
