{
  pkgs,
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
in
{
  imports = [
    ../modules/docker.nix
    (import ../modules/tools.nix).darwin
  ];

  programs.gnupg.agent.enableSSHSupport = false;
  programs.zsh = {
    enable = true;
    # Home Manager の zsh-autocomplete に補完初期化を任せる。
    enableGlobalCompInit = false;
  };

  # nix-darwin installs fonts; nix/modules/fonts configures Home Manager fontconfig clients.
  fonts.packages = (import ../modules/fonts.nix { inherit pkgs; }).fonts.packages;

  time.timeZone = "Asia/Tokyo";

  system = {
    primaryUser = user;
    stateVersion = 6;
    tools.darwin-uninstaller.enable = false;
    defaults.loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = false;
    };
  };

  nix = {
    # Keep the daemon and CLI on Lix after bootstrapping with the Lix installer.
    package = pkgs.lixPackageSets.stable.lix;

    # Use the native weekly optimiser; auto-optimise-store is unsafe on Darwin.
    optimise.automatic = true;

    settings = {
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

  users.users.${user}.home = "/Users/${user}";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} = {
      imports = [ ../home/darwin.nix ];
      xdg.enable = true;
    };
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
