{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    lib
    wsl
    ;
in
{
  testPatinaCallableLookupsAreDisabledOnlyForWsl = {
    expr = {
      wsl = builtins.fromTOML wsl.config.xdg.configFile."zsh-patina/config.toml".text;
      linuxConfigured = homeConfigurations.linux.config.xdg.configFile ? "zsh-patina/config.toml";
      darwinConfigured = homeConfigurations.darwin.config.xdg.configFile ? "zsh-patina/config.toml";
    };
    expected = {
      wsl =
        builtins.fromTOML
          (import ../../../home/wsl.nix {
            inherit inputs lib;
            inherit (wsl) pkgs;
            inherit (wsl) config;
          }).xdg.configFile."zsh-patina/config.toml".text;
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
