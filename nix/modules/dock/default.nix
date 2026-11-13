{
  config,
  lib,
  pkgs,
  ...
}:
let
  application =
    cfg: name:
    lib.optional (cfg.enable && cfg.package != null) (
      if config.targets.darwin.copyApps.enable then
        "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/${name}.app"
      else
        "${cfg.package}/Applications/${name}.app"
    );
  applications =
    application config.programs.chatgpt "ChatGPT"
    ++ application config.programs.dia "Dia"
    ++ application config.programs.ghostty "Ghostty"
    ++ application config.programs.obsidian "Obsidian";
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
      ++ applications;
      persistent-others = [ ];
      showDesktopGestureEnabled = true;
      showMissionControlGestureEnabled = true;
      showAppExposeGestureEnabled = false;
      showLaunchpadGestureEnabled = false;
    };

    home.activation.dockRegisterApplications =
      lib.mkIf (config.targets.darwin.copyApps.enable && applications != [ ])
        (
          lib.hm.dag.entryAfter [ "copyApps" ] ''
            # Register the copied Dock applications instead of store generations.
            lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
            "$lsregister" -dump | /usr/bin/sed -n \
              's|^path: *\(/nix/store/[^/]*/Applications/[^/]*\.app\) (.*$|\1|p' | \
              while IFS= read -r app; do
                case "$app" in
                  ${lib.concatMapStringsSep "|" (app: "*/${builtins.baseNameOf app}") applications})
                    run "$lsregister" -u "$app"
                    ;;
                esac
              done
            for app in ${lib.escapeShellArgs applications}; do
              run "$lsregister" -f "$app"
            done
          ''
        );
  };
}
