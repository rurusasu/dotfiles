{ fixtures, homeConfigurations }:
let
  inherit (homeConfigurations)
    homes
    lib
    linux
    wsl
    darwin
    ;
  standalone =
    (fixtures.mkHome "x86_64-linux" [
      { programs.starship.enable = true; }
    ]).config.programs.starship.settings;
  generatedSettings =
    home:
    builtins.fromJSON (
      builtins.unsafeDiscardStringContext
        home.config.home.file.${home.config.programs.starship.configPath}.source.value
    );
  windowsHelperHome =
    system: enable: integration:
    fixtures.mkHome system [
      {
        programs = {
          bash.enable = true;
          zsh.enable = true;
          starship = {
            inherit enable;
            wslIntegration.enable = integration;
          };
        };
      }
    ];
in
{
  testStarshipEnabled = {
    expr = map (home: {
      enabled = home.config.programs.starship.enable;
      ownsConfig = home.config.home.file.${home.config.programs.starship.configPath}.force;
    }) homes;
    expected = map (_: {
      enabled = true;
      ownsConfig = true;
    }) homes;
  };

  testStarshipConfiguration = {
    expr = map generatedSettings homes;
    expected = map (home: home.config.programs.starship.settings) homes;
  };

  testStarshipOperatingSystems = {
    expr = map (
      home:
      let
        settings = generatedSettings home;
        platform = home.pkgs.stdenv.hostPlatform;
      in
      {
        runtimeDetection = !settings.os.disabled;
        staticPrefix = lib.hasPrefix "[${
          if platform.isLinux then
            "❄️ "
          else if platform.isDarwin then
            "🍎 "
          else
            null
        }](${settings.os.style}) " settings.format;
        windowsHelper = settings.git_status ? windows_starship;
      }
    ) homes;
    expected =
      map
        (windowsHelper: {
          runtimeDetection = false;
          staticPrefix = true;
          inherit windowsHelper;
        })
        [
          false
          true
          false
        ];
  };

  testStarshipZshIntegration = {
    expr = map (home: {
      enabled = home.config.programs.starship.enableZshIntegration;
      initialization =
        lib.hasInfix
          (builtins.unsafeDiscardStringContext ''eval "$(${lib.getExe home.config.programs.starship.package} init zsh)"'')
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" home.config.programs.zsh.dotDir}/.zshrc".text;
    }) homes;
    expected = map (home: {
      enabled = true;
      initialization = home.config.programs.starship.enableZshIntegration;
    }) homes;
  };

  testStarshipAsyncZshSelection = {
    expr = map (home: {
      enabled = home.config.programs.starship.asyncZsh.enable;
      initialized = lib.hasInfix (builtins.unsafeDiscardStringContext "${home.config.programs.starship.asyncZsh.package}/share/zsh/site-functions/async") home.config.programs.zsh.initContent;
    }) homes;
    expected =
      map
        (enabled: {
          inherit enabled;
          initialized = enabled;
        })
        [
          false
          true
          false
        ];
  };

  testStarshipConfigLocation = {
    expr = {
      wsl = wsl.config.home.sessionVariables.STARSHIP_CONFIG;
      linux = linux.config.home.sessionVariables.STARSHIP_CONFIG;
      darwin = darwin.config.home.sessionVariables.STARSHIP_CONFIG;
    };
    expected = {
      wsl = toString wsl.config.home.file.${wsl.config.programs.starship.configPath}.source;
      linux = linux.config.programs.starship.configPath;
      darwin = darwin.config.programs.starship.configPath;
    };
  };

  testStarshipStandaloneLinux = {
    expr = {
      runtimeDetection = !standalone.os.disabled;
      staticPrefix = lib.hasPrefix "[❄️ ](${standalone.os.style}) " standalone.format;
    };
    expected = {
      runtimeDetection = false;
      staticPrefix = true;
    };
  };

  testStarshipWindowsHelperEnableBoundary = {
    expr =
      map
        (
          home:
          let
            settings = home.config.programs.starship.settings;
            helper = settings.git_status.windows_starship or null;
          in
          {
            absoluteHelper = helper != null && lib.hasPrefix "${builtins.storeDir}/" helper;
            bashLookup = lib.hasInfix "DOTFILES_WINDOWS_STARSHIP" home.config.programs.bash.initExtra;
            zshLookup = lib.hasInfix "DOTFILES_WINDOWS_STARSHIP" home.config.programs.zsh.initContent;
          }
        )
        [
          (windowsHelperHome "x86_64-linux" true true)
          (windowsHelperHome "x86_64-linux" true false)
          (windowsHelperHome "x86_64-linux" false true)
          (windowsHelperHome "aarch64-darwin" true true)
        ];
    expected =
      map
        (enabled: {
          absoluteHelper = enabled;
          bashLookup = enabled;
          zshLookup = enabled;
        })
        [
          true
          false
          false
          false
        ];
  };
}
