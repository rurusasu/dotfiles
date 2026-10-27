{
  config,
  inputs,
  pkgs,
  ...
}:
{
  targets.darwin.defaults."com.apple.dock" = {
    tilesize = 50;
    autohide = true;
    launchanim = true;
    show-process-indicators = true;
    show-recents = false;
    persistent-apps = [
      "${config.programs.chatgpt.package}/Applications/ChatGPT.app"
      "${import ./browsers/dia { inherit inputs pkgs; }}/Applications/Dia.app"
      "${config.programs.ghostty.package}/Applications/Ghostty.app"
      "${pkgs.obsidian}/Applications/Obsidian.app"
    ];
    persistent-others = [ ];
    showDesktopGestureEnabled = true;
    showMissionControlGestureEnabled = true;
    showAppExposeGestureEnabled = false;
    showLaunchpadGestureEnabled = false;
  };
}
