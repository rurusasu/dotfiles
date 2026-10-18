{
  config,
  pkgs,
  lib,
  inputs,
  sudoUser,
  currentUser,
  ...
}:
let
  user =
    if sudoUser != "" then
      sudoUser
    else if currentUser != "" then
      currentUser
    else
      throw "Unable to determine the macOS user: SUDO_USER and USER are both empty.";
  home = "/Users/${user}";
  gibibyte = 1024 * 1024 * 1024;
  bundledAppCleanup = import ./remove-bundled-apps.nix { inherit pkgs; };
in
{
  imports = [
    ../../modules/docker.nix
    ./omarchy-keybindings.nix
    ../../modules/desktop-darwin.nix
    (import ../../modules/tools.nix).darwin
  ];

  system = {
    primaryUser = user;
    stateVersion = 6;
    tools.darwin-uninstaller.enable = false;
    activationScripts = {
      postActivation.text = lib.mkBefore ''
        ${lib.getExe bundledAppCleanup} /Applications
      '';
      globalZoomShortcut.text = ''
        uid="$(id -u -- ${lib.escapeShellArg user})"
        runAsUser() {
          launchctl asuser "$uid" sudo --user=${lib.escapeShellArg user} -- "$@"
        }

        runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"
        runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"
      '';
    };
  };

  nix = {
    # Keep the daemon and CLI on Lix after bootstrapping with the Lix installer.
    package =
      let
        lix = pkgs.lixPackageSets.stable.lix;
      in
      lix.overrideAttrs (old: {
        # The mimalloc Meson option was introduced in Lix 2.96.
        mesonFlags = lib.filter (
          flag: lib.versionAtLeast lix.version "2.96" || !(lib.hasPrefix "-Dmimalloc=" flag)
        ) old.mesonFlags;
      });

    # Collect weekly, keeping only the current generation of each profile.
    gc = {
      automatic = true;
      interval = [
        {
          Weekday = 7;
          Hour = 3;
          Minute = 15;
        }
      ];
      options = "--delete-old";
    };

    # Use the native weekly optimiser; auto-optimise-store is unsafe on Darwin.
    optimise.automatic = true;

    settings = {
      # During builds, collect unreferenced paths when free space falls below 10 GiB.
      min-free = 10 * gibibyte;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
  };

  # nix-darwin's generated documentation currently passes a removed
  # nixos-render-docs flag. Omit the optional manual artifacts and the
  # uninstaller's nested default system, which otherwise rebuilds them.
  documentation.enable = false;

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    inherit user;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    brews = [ ];
    casks = [
      "docker-desktop"
      "steam"
    ];
    # nix-darwin installs and upgrades declared casks through Homebrew Bundle.
    greedyCasks = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # Remove undeclared Homebrew packages, including cask-defined settings/data.
      cleanup = "zap";
      extraEnv = {
        HOMEBREW_AUTO_UPDATE_SECS = "86400";
        HOMEBREW_NO_ENV_HINTS = "1";
      };
    };
  };

  users.users.${user}.home = home;

  # GUI apps use the same 1Password socket as Home Manager's shell sessions.
  launchd.user.envVariables.SSH_AUTH_SOCK =
    config.home-manager.users.${user}.home.sessionVariables.SSH_AUTH_SOCK;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} = {
      imports = [ ./home.nix ];
      xdg.enable = true;
    };
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
