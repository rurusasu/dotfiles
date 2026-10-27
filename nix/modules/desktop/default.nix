{
  config,
  lib,
  pkgs,
  ...
}:
let
  trackpad = {
    Clicking = true;
    TrackpadRightClick = true;
  };
in
{
  options.dotfiles.desktop.enable = lib.mkEnableOption "the macOS desktop preferences";

  config = lib.mkIf (config.dotfiles.desktop.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    targets.darwin.defaults = {
      "com.apple.AppleMultitouchTrackpad" = trackpad;
      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = trackpad;
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        "com.apple.swipescrolldirection" = true;
        AppleInterfaceStyle = "Dark";
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
      };
    };

    # Dictionary additions preserve unrelated application-specific shortcuts.
    home.activation.globalZoomShortcut = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"
      run /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"
    '';

    home.activation.refreshDarwinSettings =
      lib.hm.dag.entryAfter
        [
          "setDarwinDefaults"
          "globalZoomShortcut"
          "omarchySymbolicHotkeys"
        ]
        ''
          if /usr/bin/pgrep -u "$UID" -x Dock >/dev/null; then
            run /usr/bin/killall -qu ${lib.escapeShellArg config.home.username} Dock
          fi
          run /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
        '';
  };
}
