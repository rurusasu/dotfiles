{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
  inherit ((import ../fixtures/packages.nix { inherit inputs; })) mkPkgs;
  mkHome =
    system:
    let
      pkgs = mkPkgs system;
    in
    import "${inputs.home-manager}/lib/eval-config.nix" {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ../../home/common.nix
        ../../modules/editors/nvim
        {
          home = {
            username = "test-user";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
            stateVersion = "26.05";
          };
        }
      ];
    };
in
{
  testAppearanceIsNixOwned = {
    expr = import ../../modules/terminals/appearance.nix;
    expected = {
      font_family = "UDEV Gothic NF";
      font_size = 10;
      theme = "Catppuccin Mocha";
    };
  };
  testWezTermUsesSharedAppearance = {
    expr = map (
      system:
      let
        cfg = (mkHome system).config.programs.wezterm;
      in
      {
        inherit system;
        font =
          cfg.settings.font
          == (mkPkgs system).lib.generators.mkLuaInline "wezterm.font(${builtins.toJSON (import ../../modules/terminals/appearance.nix).font_family})";
        font_size = cfg.settings.font_size;
        color_scheme = cfg.settings.color_scheme;
      }
    ) systems;
    expected = map (system: {
      inherit system;
      font = true;
      font_size = 10;
      color_scheme = "Catppuccin Mocha";
    }) systems;
  };
  testTerminalToolsUseNativeHomeManagerModules = {
    expr = map (
      system:
      let
        home = mkHome system;
        cfg = home.config;
      in
      {
        inherit system;
        lazygit = cfg.programs.lazygit.enable;
        herdr = cfg.programs.herdr.enable;
        bashWrapper = home.pkgs.lib.hasInfix "function lg()" cfg.programs.bash.initExtra;
        zshWrapper = home.pkgs.lib.hasInfix "function lg()" cfg.programs.zsh.initContent;
        herdrConfig = cfg.programs.herdr.settings;
      }
    ) systems;
    expected = map (system: {
      inherit system;
      lazygit = true;
      herdr = true;
      bashWrapper = true;
      zshWrapper = true;
      herdrConfig = (import ../../modules/herdr/default.nix { }).programs.herdr.settings;
    }) systems;
  };
}
