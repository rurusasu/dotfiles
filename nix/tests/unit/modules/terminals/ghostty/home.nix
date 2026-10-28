{ homeConfigurations, code }:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
  appearance = code.nix.modules.terminals.appearance;
  ghosttyBase = {
    theme = [ appearance.theme ];
    font-family = [ appearance.font_family ];
    font-size = [ appearance.font_size ];
    macos-option-as-alt = [ true ];
  };
  fromWindowsExport =
    home: lib.attrByPath [ "dotfiles" "keybindings" "fromWindowsExport" ] false home.config;
  keybindingConfig =
    home:
    if fromWindowsExport home then
      { config-file = [ "?${home.config.xdg.configHome}/dotfiles/keybindings/ghostty.conf" ]; }
    else
      {
        keybind = code.nix.modules.terminals.ghostty.ghostty-renderer {
          inherit lib;
          bindings = (code.nix.home.keybindings.bindings { inherit lib; }).ghostty;
          asList = true;
        };
      };
in
{
  testGhosttyConfigurationUsesEachHomesOptionsAndCanonicalSources = {
    expr = map (home: {
      enabled = home.config.programs.ghostty.enable;
      config = home.config.programs.ghostty.settings;
      source = toString home.config.xdg.configFile."ghostty/config".source;
      validateCommand = home.config.xdg.configFile."ghostty/config".onChange;
    }) homes;
    expected = map (home: {
      enabled = true;
      config = ghosttyBase // keybindingConfig home;
      source = toString (
        (home.pkgs.formats.keyValue {
          listsAsDuplicateKeys = true;
          mkKeyValue = lib.generators.mkKeyValueDefault { } " = ";
        }).generate
          "ghostty-config"
          (ghosttyBase // keybindingConfig home)
      );
      validateCommand = "${home.config.programs.ghostty.package}/bin/ghostty +validate-config --config-file=${home.config.xdg.configHome}/ghostty/config";
    }) homes;
  };

  testGhosttyKeybindingSourcesKeepTheirPlatformAllocation = {
    expr = {
      wsl = fromWindowsExport homeConfigurations.wsl;
      linux = fromWindowsExport homeConfigurations.linux;
      darwin = fromWindowsExport homeConfigurations.darwin;
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
      in
      {
        bashGhostty =
          lib.hasInfix "shell-integration/bash/ghostty.bash"
            config.home.file.".bashrc".source.text;
        zshGhostty =
          lib.hasInfix "shell-integration/zsh/ghostty-integration"
            config.home.file."${lib.removePrefix "${config.home.homeDirectory}/" config.programs.zsh.dotDir}/.zshrc".text;
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
