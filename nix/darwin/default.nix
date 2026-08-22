{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  user = builtins.getEnv "DOTFILES_USER";
  home = builtins.getEnv "DOTFILES_HOME";
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
in
{
  assertions = [
    {
      assertion = user != "";
      message = "DOTFILES_USER is required";
    }
    {
      assertion = home != "";
      message = "DOTFILES_HOME is required";
    }
  ];

  system = {
    primaryUser = user;
    stateVersion = 6;
    tools.darwin-uninstaller.enable = false;
    activationScripts.globalZoomShortcut.text = ''
      uid="$(id -u -- ${lib.escapeShellArg user})"
      runAsUser() {
        launchctl asuser "$uid" sudo --user=${lib.escapeShellArg user} -- "$@"
      }

      runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"
      runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"
    '';
  };

  system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
    "60" = {
      enabled = false;
      value = {
        parameters = [
          32
          49
          1048576
        ];
        type = "standard";
      };
    };
    "61" = {
      enabled = false;
      value = {
        parameters = [
          32
          49
          1572864
        ];
        type = "standard";
      };
    };
    "64" = {
      enabled = false;
      value = {
        parameters = [
          65535
          49
          1048576
        ];
        type = "standard";
      };
    };
    "65" = {
      enabled = false;
      value = {
        parameters = [
          65535
          49
          1572864
        ];
        type = "standard";
      };
    };
    "156" = {
      enabled = false;
      value = {
        parameters = [
          65535
          49
          393216
        ];
        type = "standard";
      };
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

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
    brews = sets.darwinBrews;
    casks = sets.darwinCasks;
    # nix-darwin installs and upgrades declared casks through Homebrew Bundle.
    greedyCasks = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "none";
      extraEnv = {
        HOMEBREW_AUTO_UPDATE_SECS = "86400";
        HOMEBREW_NO_ENV_HINTS = "1";
      };
    };
  };

  users.users.${user}.home = home;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} =
      { ... }:
      {
        imports = [ ../home/common.nix ];

        programs.zsh.shellAliases = {
          nrs = "~/.dotfiles/install.sh";
        };
      };
    extraSpecialArgs = {
      inherit inputs;
      isWSL = false;
    };
  };
}
