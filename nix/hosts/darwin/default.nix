{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  user = builtins.getEnv "DOTFILES_USER";
  home = builtins.getEnv "DOTFILES_HOME";
  codexPackage = inputs."llm-agents".packages.${pkgs.stdenv.hostPlatform.system}.codex;
  sets = import ../../packages/sets.nix {
    inherit pkgs lib;
    inherit codexPackage;
  };
  discordPackage = sets.darwinDiscordPackage;
  withHermes = builtins.getEnv "DOTFILES_WITH_HERMES" == "1";
  withDocker = withHermes || builtins.getEnv "DOTFILES_WITH_DOCKER" == "1";
  withOllama = withDocker || builtins.getEnv "DOTFILES_WITH_OLLAMA" == "1";
  installFeatures =
    lib.optionals withOllama [ "WithOllama" ]
    ++ lib.optionals withDocker [ "WithDocker" ]
    ++ lib.optionals withHermes [ "WithHermes" ];
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
    activationScripts.removeLegacyOmlx.text = ''
      brew="/opt/homebrew/bin/brew"
      if [ -x "$brew" ]; then
        uid="$(id -u -- ${lib.escapeShellArg user})"
        runAsUser() {
          launchctl asuser "$uid" sudo --user=${lib.escapeShellArg user} --set-home -- "$@"
        }

        if runAsUser "$brew" list --formula --versions omlx >/dev/null 2>&1; then
          runAsUser "$brew" uninstall --formula omlx
        fi
        if runAsUser "$brew" tap | ${lib.getExe pkgs.gnugrep} --fixed-strings --line-regexp --quiet "jundot/omlx"; then
          runAsUser "$brew" untap jundot/omlx
        fi
      fi
    '';
    activationScripts.postActivation.text = lib.mkAfter (
      lib.optionalString withHermes ''
        uid="$(id -u -- ${lib.escapeShellArg user})"
        runAsUser() {
          launchctl asuser "$uid" sudo --user=${lib.escapeShellArg user} --set-home -- "$@"
        }

        runAsUser ${lib.getExe discordPackage.passthru.disableBreakingUpdates}
      ''
    );
  };

  launchd.user.agents.com-dotfiles-ollama = lib.mkIf withOllama {
    serviceConfig = {
      ProgramArguments = [
        (lib.getExe pkgs.ollama)
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables = {
        HOME = home;
      };
      StandardOutPath = "${home}/Library/Logs/Ollama/ollama.log";
      StandardErrorPath = "${home}/Library/Logs/Ollama/ollama.error.log";
    };
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

  launchd.user.agents.discord-module-staging = lib.mkIf withHermes {
    serviceConfig = {
      ProgramArguments = [
        "${discordPackage.passthru.stageModules}"
        "${discordPackage}/share/discord/modules"
      ];
      RunAtLoad = true;
      KeepAlive.PathState = {
        "${home}/Library/Application Support/discord/${discordPackage.version}/modules/installed.json" =
          false;
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
    casks = sets.darwinCasksForInstallFeatures installFeatures;
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

  environment.systemPackages =
    sets.darwinSystemPackagesForInstallFeatures installFeatures ++ sets.hostPackages;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} = {
      imports = [ ../../home/darwin.nix ];
    };
    extraSpecialArgs = {
      inherit inputs installFeatures;
      isWSL = false;
    };
  };
}
