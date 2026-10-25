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
  nativeConfig = ghosttyBase + "\n" + allocation.ghosttyConfig;
in
{
  testGhosttyKeybindingsUsePlatformSourcesAcrossHomes = {
    expr = {
      wsl = wsl.config.xdg.configFile."ghostty/config".text;
      linux = linux.config.xdg.configFile."ghostty/config".text;
      darwin = darwin.config.xdg.configFile."ghostty/config".text;
    };
    expected = {
      wsl =
        ghosttyBase + "\nconfig-file = ?${wsl.config.xdg.configHome}/dotfiles/keybindings/ghostty.conf\n";
      linux = nativeConfig;
      darwin = nativeConfig;
    };
  };

  testGhosttyShellIntegrationsAreGeneratedAcrossHomes = {
    expr = map (home: {
      bashGhostty = lib.hasInfix "shell-integration/bash/ghostty.bash" home.config.programs.bash.initExtra;
      zshGhostty = lib.hasInfix "shell-integration/zsh/ghostty-integration" home.config.programs.zsh.initContent;
    }) homes;
    expected = map (_: {
      bashGhostty = true;
      zshGhostty = true;
    }) homes;
  };
}
