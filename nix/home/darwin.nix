{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  trackpad = {
    Clicking = true;
    TrackpadRightClick = true;
  };
  dockerHost = "unix://${config.home.homeDirectory}/.docker/run/docker.sock";
  logDirectory = "${config.home.homeDirectory}/Library/Logs";
in
{
  imports = [
    (import ../modules/tools.nix).chatgpt
    ./keybindings/darwin.nix
    ../modules/discord
    ./common.nix
  ];

  home = {
    # System integration supplies the host home with higher priority.
    homeDirectory = lib.mkDefault "/Users/${config.home.username}";

    sessionVariables = {
      # Homebrew's default is already 24 hours; keep that interval explicit
      # for interactive shells and tools launched from the Home Manager session.
      HOMEBREW_AUTO_UPDATE_SECS = "86400";
      # Let native op use the unlocked 1Password desktop app integration.
      OP_BIOMETRIC_UNLOCK_ENABLED = "true";
    };

    sessionPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
    ];
  };

  programs.git.signing.signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

  targets.darwin.defaults = {
    "com.apple.dock" = {
      tilesize = 50;
      autohide = true;
      launchanim = true;
      show-process-indicators = true;
      show-recents = false;
      persistent-apps = [
        "/System/Applications/Apps.app"
        "${config.home.homeDirectory}/Applications/Home Manager Apps/ChatGPT.app"
        "/Applications/Nix Apps/Dia.app"
        "${config.home.homeDirectory}/Applications/Home Manager Apps/Ghostty.app"
        "/Applications/Nix Apps/Obsidian.app"
      ];
      persistent-others = [ ];
      showDesktopGestureEnabled = true;
      showMissionControlGestureEnabled = true;
      showAppExposeGestureEnabled = false;
      showLaunchpadGestureEnabled = false;
    };

    "com.apple.AppleMultitouchTrackpad" = trackpad;
    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = trackpad;

    "com.apple.finder" = {
      NewWindowTarget = "PfHm";
      _FXShowPosixPathInTitle = true;
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = true;
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };

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

  # GUI apps use the same 1Password socket as this user's shell sessions.
  launchd.agents.onepassword-ssh-environment = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/launchctl"
        "setenv"
        "SSH_AUTH_SOCK"
        config.home.sessionVariables.SSH_AUTH_SOCK
      ];
      RunAtLoad = true;
    };
  };

  launchd.agents.tool-cache-maintenance = {
    enable = true;
    config = {
      ProgramArguments = [
        (lib.getExe (
          pkgs.writeShellApplication {
            name = "tool-cache-maintenance";
            runtimeInputs = [
              pkgs.uv
              pkgs.go
            ];
            text = ''
              status=0

              run_cleanup() {
                local name="$1"
                shift
                printf 'Cleaning %s cache\n' "$name"
                if "$@"; then
                  printf 'Finished %s cache cleanup\n' "$name"
                else
                  local result=$?
                  printf '%s cache cleanup failed (exit %s)\n' "$name" "$result" >&2
                  status=1
                fi
              }

              run_cleanup uv uv cache prune
              # Keep downloaded modules and project outputs; rebuild this cache as needed.
              run_cleanup go go clean -cache

              # Cargo already garbage-collects its global cache. Do not sweep project target/.
              if command -v docker >/dev/null 2>&1; then
                # Pin Docker Desktop's local socket, regardless of context/environment overrides.
                if docker --host ${lib.escapeShellArg dockerHost} info --format '{{.ServerVersion}}' >/dev/null; then
                  run_cleanup docker docker --host ${lib.escapeShellArg dockerHost} builder prune --force
                else
                  printf 'Skipping Docker build cache: local Docker Desktop is unavailable\n' >&2
                fi
              else
                printf 'Skipping Docker build cache: Docker CLI is unavailable\n' >&2
              fi

              exit "$status"
            '';
          }
        ))
      ];
      EnvironmentVariables.PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin";
      StartCalendarInterval =
        if osConfig != null then
          osConfig.nix.gc.interval
        else
          lib.hm.darwin.mkCalendarInterval (builtins.head config.nix.gc.dates);
      RunAtLoad = false;
      ProcessType = "Background";
      StandardOutPath = "${logDirectory}/tool-cache-maintenance.log";
      StandardErrorPath = "${logDirectory}/tool-cache-maintenance.log";
    };
  };

  home.activation.cacheMaintenanceLogDirectory = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
    run mkdir -p -- ${lib.escapeShellArg logDirectory}
  '';
}
