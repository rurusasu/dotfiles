{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    lib
    linux
    wsl
    darwin
    ;
  standalone =
    ((import ../../fixtures/packages.nix { inherit inputs; }).mkHome "x86_64-linux" [
      ../../../modules/shells/plugins/starship
      { programs.starship.enable = true; }
    ]).config.programs.starship.settings;
  generatedSettings =
    home:
    builtins.fromJSON home.config.home.file.${home.config.programs.starship.configPath}.source.value;
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
        windowsHelper = settings.git_status.windows_starship or null;
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
          null
          "starship.exe"
          null
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
}
