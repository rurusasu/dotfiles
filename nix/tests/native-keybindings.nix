{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  inherit (pkgs) lib;
  native = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ../hosts/linux/configuration.nix
      {
        nixpkgs.pkgs = pkgs;
        home-manager.useGlobalPkgs = true;
        home-manager.users.test = {
          home.username = "test";
          home.homeDirectory = "/home/test";
          home.stateVersion = "25.05";
        };
      }
    ];
  };
  cfg = native.config;
  home = cfg.home-manager.users.test;
  sets = import ../packages/sets.nix { inherit pkgs lib; };
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
  testNativeDesktopProviderIsOptIn = {
    expr = {
      defaultPackages = map (package: package.pname) (
        sets.resolveForInstallFeatures [ ] [ "hyprland" "fuzzel" ]
      );
      selectedPackages = map (package: package.pname) (
        sets.resolveForInstallFeatures [ "WithDesktop" ] [ "hyprland" "fuzzel" ]
      );
      providerErrors = sets.providerErrors;
    };
    expected = {
      defaultPackages = [ ];
      selectedPackages = [
        "hyprland"
        "fuzzel"
      ];
      providerErrors = [ ];
    };
  };
}
