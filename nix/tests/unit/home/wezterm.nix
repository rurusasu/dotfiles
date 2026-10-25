{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
  declaredWezterm =
    home:
    (import ../../../modules/terminals/wezterm/defaults.nix {
      inherit (home) config pkgs;
      inherit (home.pkgs) lib;
    }).programs.wezterm;
  shellSource = home: ''source "${home.config.programs.wezterm.package}/etc/profile.d/wezterm.sh"'';
in
{
  testWeztermLuaIncludesEachHomesSettingsAndExtraConfig = {
    expr = map (
      home:
      let
        cfg = home.config.programs.wezterm;
        lua = home.config.xdg.configFile."wezterm/wezterm.lua".text;
      in
      {
        enabled = cfg.enable;
        settings = lib.hasInfix (builtins.unsafeDiscardStringContext (
          lib.generators.toLua { } cfg.settings
        )) lua;
        extraConfig = lib.hasInfix (builtins.unsafeDiscardStringContext cfg.extraConfig) lua;
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      settings = true;
      extraConfig = true;
    }) homes;
  };

  testWeztermExtraConfigRetainsTheCanonicalLua = {
    expr = map (home: home.config.programs.wezterm.extraConfig) homes;
    expected = map (home: (declaredWezterm home).extraConfig) homes;
  };

  testWeztermShellIntegrationsAreGeneratedAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home) config;
        zshDirectory = lib.removePrefix "${config.home.homeDirectory}/" config.programs.zsh.dotDir;
      in
      {
        bashWezterm = lib.hasInfix (builtins.unsafeDiscardStringContext (
          shellSource home
        )) config.home.file.".bashrc".source.text;
        zshWezterm = lib.hasInfix (builtins.unsafeDiscardStringContext (
          shellSource home
        )) config.home.file."${zshDirectory}/.zshrc".text;
      }
    ) homes;
    expected = map (_: {
      bashWezterm = true;
      zshWezterm = true;
    }) homes;
  };
}
