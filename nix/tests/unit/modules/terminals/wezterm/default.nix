{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
  inherit ((import ../../../../fixtures/packages.nix { inherit inputs; })) mkPkgs;
in
{
  testWezTermUsesSharedAppearance = {
    expr = map (
      system:
      let
        cfg =
          let
            pkgs = mkPkgs system;
          in
          (import "${inputs.home-manager}/lib/eval-config.nix" {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs; };
            modules = [
              ((import ../../../../fixtures/packages.nix { inherit inputs; }).homeModule "common")
              ../../../../../modules/editors/nvim
              {
                home = {
                  username = "test-user";
                  homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
                  stateVersion = "26.05";
                };
              }
            ];
          }).config.programs.wezterm;
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
