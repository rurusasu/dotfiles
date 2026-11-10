{
  config,
  lib,
  pkgs,
  ...
}:
let
  application =
    cfg: name:
    lib.optional (cfg.enable && cfg.package != null) "${cfg.package}/Applications/${name}.app";
in
{
  config = lib.mkIf (config.dotfiles.desktop.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    targets.darwin.defaults."com.apple.dock" = {
      tilesize = 50;
      autohide = true;
      launchanim = true;
      show-process-indicators = true;
      show-recents = false;
      persistent-apps = [
        { app = "/System/Applications/Apps.app"; }
      ]
      ++ application config.programs.chatgpt "ChatGPT"
      ++ application config.programs.dia "Dia"
      ++ application config.programs.ghostty "Ghostty"
      ++ [ "${pkgs.obsidian}/Applications/Obsidian.app" ];
      persistent-others = [ ];
      showDesktopGestureEnabled = true;
      showMissionControlGestureEnabled = true;
      showAppExposeGestureEnabled = false;
      showLaunchpadGestureEnabled = false;
    };
  };
}
