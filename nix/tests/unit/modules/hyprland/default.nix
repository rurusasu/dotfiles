{ inputs }:
let
  pkgs = (import ../../../fixtures/packages.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  home =
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        platform = "linux";
      };
      modules = [
        (import ../../../../defaults.nix inputs).systemDefaults
        {
          nixpkgs.pkgs = pkgs;
          users.users.nixos.home = "/srv/nixos";
        }
      ];
    }).config.home-manager.users.nixos;
in
{
  testNativeHomeGeneratesLuaFromSharedKeys = {
    expr = {
      enabled = home.wayland.windowManager.hyprland.enable;
      format = home.wayland.windowManager.hyprland.configType;
      generated = pkgs.lib.hasInfix ''hl.bind("SUPER + 0", hl.dsp.focus({ workspace = "10" }),'' (
        home.xdg.configFile."hypr/hyprland.lua".text or ""
      );
      systemOwnsCompositor = home.wayland.windowManager.hyprland.package == null;
    };
    expected = {
      enabled = true;
      format = "lua";
      generated = true;
      systemOwnsCompositor = true;
    };
  };
}
