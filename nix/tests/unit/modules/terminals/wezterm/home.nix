{
  inputs,
  homeConfigurations ? import ../../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
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
        terminfoDeclaration = lib.hasInfix (builtins.unsafeDiscardStringContext "local dotfiles_terminfo_directory = ${lib.generators.toLua { } "${cfg.package.terminfo}/share/terminfo"}") lua;
      }
    ) homes;
    expected = map (home: {
      enabled = true;
      settings = true;
      extraConfig = true;
      terminfoDeclaration = home.pkgs.stdenv.hostPlatform.isDarwin;
    }) homes;
  };

  testWeztermExtraConfigRetainsTheCanonicalLua = {
    expr = map (
      home:
      lib.hasSuffix (builtins.readFile ../../../../../modules/terminals/wezterm/wezterm.lua) home.config.programs.wezterm.extraConfig
    ) homes;
    expected = map (_: true) homes;
  };

  testWeztermShellIntegrationsAreGeneratedAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home) config;
      in
      {
        bashWezterm = lib.hasInfix (builtins.unsafeDiscardStringContext (
          shellSource home
        )) config.home.file.".bashrc".source.text;
        zshWezterm =
          lib.hasInfix (builtins.unsafeDiscardStringContext (shellSource home))
            config.home.file."${lib.removePrefix "${config.home.homeDirectory}/" config.programs.zsh.dotDir}/.zshrc".text;
      }
    ) homes;
    expected = map (_: {
      bashWezterm = true;
      zshWezterm = true;
    }) homes;
  };
}
