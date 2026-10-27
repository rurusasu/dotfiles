{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
  fixtures = import ../../../../fixtures/packages.nix { inherit inputs; };
  inherit (fixtures) mkPkgs;
in
{
  testWezTermUsesSharedAppearance = {
    expr = map (
      system:
      let
        cfg = (fixtures.mkHome system [ { programs.wezterm.enable = true; } ]).config.programs.wezterm;
      in
      {
        inherit system;
        font =
          cfg.settings.font
          == (mkPkgs system).lib.generators.mkLuaInline "wezterm.font(${builtins.toJSON (import ../../../../../modules/terminals/appearance.nix).font_family})";
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
}
