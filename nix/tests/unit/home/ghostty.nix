{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    linux
    wsl
    darwin
    homes
    lib
    ;
  ghosttyBase = builtins.readFile ../../../modules/terminals/ghostty/config.ghostty;
  allocation = import ../../../home/keybindings/bindings.nix { inherit lib; };
  fromWindowsExport =
    home: lib.attrByPath [ "dotfiles" "keybindings" "fromWindowsExport" ] false home.config;
  keybindingConfig =
    home:
    if fromWindowsExport home then
      "config-file = ?${home.config.xdg.configHome}/dotfiles/keybindings/ghostty.conf\n"
    else
      allocation.ghosttyConfig;
in
{
  testGhosttyConfigurationUsesEachHomesOptionsAndCanonicalSources = {
    expr = map (home: {
      enabled = home.config.programs.ghostty.enable;
      config = home.config.xdg.configFile."ghostty/config".text;
      validateCommand = home.config.xdg.configFile."ghostty/config".onChange;
    }) homes;
    expected = map (home: {
      enabled = true;
      config = ghosttyBase + "\n" + keybindingConfig home;
      validateCommand = "${home.config.programs.ghostty.package}/bin/ghostty +validate-config --config-file=${home.config.xdg.configHome}/ghostty/config";
    }) homes;
  };

  testGhosttyKeybindingSourcesKeepTheirPlatformAllocation = {
    expr = {
      wsl = fromWindowsExport wsl;
      linux = fromWindowsExport linux;
      darwin = fromWindowsExport darwin;
    };
    expected = {
      wsl = true;
      linux = false;
      darwin = false;
    };
  };

  testGhosttyShellIntegrationsAreGeneratedAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home) config;
        zshDirectory = lib.removePrefix "${config.home.homeDirectory}/" config.programs.zsh.dotDir;
      in
      {
        bashGhostty =
          lib.hasInfix "shell-integration/bash/ghostty.bash"
            config.home.file.".bashrc".source.text;
        zshGhostty =
          lib.hasInfix "shell-integration/zsh/ghostty-integration"
            config.home.file."${zshDirectory}/.zshrc".text;
      }
    ) homes;
    expected = map (home: {
      bashGhostty =
        home.config.programs.ghostty.enable && home.config.programs.ghostty.enableBashIntegration;
      zshGhostty =
        home.config.programs.ghostty.enable && home.config.programs.ghostty.enableZshIntegration;
    }) homes;
  };
}
