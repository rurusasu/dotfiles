{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  inherit (pkgs) lib;
  native = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ../../hosts/shared/nixos/configuration.nix
      {
        nixpkgs.pkgs = pkgs;
        home-manager.useGlobalPkgs = true;
        home-manager.users.test = {
          home = {
            username = "test";
            homeDirectory = "/home/test";
            stateVersion = "25.05";
          };
        };
      }
    ];
  };
  cfg = native.config;
  home = cfg.home-manager.users.test;
in
{
  testNativeHostSelectsHyprlandUserModule = {
    expr = cfg.programs.hyprland.enable;
    expected = true;
  };
  testNativeHomeGeneratesLuaFromSharedKeys = {
    expr = {
      enabled = home.wayland.windowManager.hyprland.enable;
      format = home.wayland.windowManager.hyprland.configType;
      generated = lib.hasInfix ''hl.bind("SUPER + 0", hl.dsp.focus({ workspace = "10" }),'' (
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
  testNativeDesktopModulesSelectTheirPackages = {
    expr = {
      compositor = builtins.elem cfg.programs.hyprland.package cfg.environment.systemPackages;
      launcher = builtins.elem pkgs.fuzzel home.home.packages;
    };
    expected = {
      compositor = true;
      launcher = true;
    };
  };
}
