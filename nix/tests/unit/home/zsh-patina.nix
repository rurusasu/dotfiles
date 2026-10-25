{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  fixtures = homeConfigurations;
  inherit (fixtures)
    darwin
    homes
    lib
    linux
    wsl
    ;
  wslSettings = import ../../../hosts/x86_64-linux/wsl/home.nix {
    inherit inputs lib;
    inherit (wsl) pkgs;
    inherit (wsl) config;
  };
in
{
  testPatinaCallableLookupsAreDisabledOnlyForWsl = {
    expr = {
      wsl = builtins.fromTOML wsl.config.xdg.configFile."zsh-patina/config.toml".text;
      linuxConfigured = linux.config.xdg.configFile ? "zsh-patina/config.toml";
      darwinConfigured = darwin.config.xdg.configFile ? "zsh-patina/config.toml";
    };
    expected = {
      wsl = builtins.fromTOML wslSettings.xdg.configFile."zsh-patina/config.toml".text;
      linuxConfigured = false;
      darwinConfigured = false;
    };
  };

  testPatinaActivatesAfterOtherZshIntegrationsAcrossHomes = {
    expr = map (
      home:
      let
        zshrc =
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" home.config.programs.zsh.dotDir}/.zshrc".text;
      in
      lib.hasSuffix ''eval "$(${lib.getExe home.pkgs.zsh-patina} activate)"'' (lib.trim zshrc)
    ) homes;
    expected = map (_: true) homes;
  };
}
