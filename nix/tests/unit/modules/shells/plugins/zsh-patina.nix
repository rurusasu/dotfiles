{
  inputs,
  homeConfigurations ? import ../../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
in
{
  testPatinaCallableLookupsAreDisabledOnlyForWsl = {
    expr = {
      wsl = builtins.fromTOML homeConfigurations.wsl.config.xdg.configFile."zsh-patina/config.toml".text;
      linuxConfigured = homeConfigurations.linux.config.xdg.configFile ? "zsh-patina/config.toml";
      darwinConfigured = homeConfigurations.darwin.config.xdg.configFile ? "zsh-patina/config.toml";
    };
    expected = {
      wsl.highlighting.dynamic = {
        callables = false;
        paths = "complete";
      };
      linuxConfigured = false;
      darwinConfigured = false;
    };
  };

  testPatinaActivatesAfterOtherZshIntegrationsAcrossHomes = {
    expr = map (
      home:
      lib.hasSuffix ''eval "$(${lib.getExe home.pkgs.zsh-patina} activate)"'' (
        lib.trim
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" home.config.programs.zsh.dotDir}/.zshrc".text
      )
    ) homes;
    expected = map (_: true) homes;
  };
}
