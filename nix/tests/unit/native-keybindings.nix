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
        home-manager.extraSpecialArgs = { inherit inputs; };
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
  sets = import ../../packages/sets.nix { inherit pkgs lib; };
in
{
  testNativeHostSelectsHyprlandUserModule = {
    expr = cfg.programs.hyprland.enable;
    expected = true;
  };
  testNativeHomeInstallsChatGPTAndBundledCodex = {
    expr = {
      chatgpt = builtins.elem "chatgpt" (map lib.getName home.home.packages);
      codex = builtins.elem "codex" (map lib.getName home.home.packages);
      aiShortcut = lib.hasInfix "chatgpt" home.wayland.windowManager.hyprland.extraConfig;
    };
    expected = {
      chatgpt = true;
      codex = true;
      aiShortcut = true;
    };
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
  testNativeDesktopProviderResolvesSelectedPackages = {
    expr = {
      selectedPackages = map (package: package.pname) (
        sets.resolve [
          "hyprland"
          "fuzzel"
        ]
      );
      inherit (sets) providerErrors;
    };
    expected = {
      selectedPackages = [
        "hyprland"
        "fuzzel"
      ];
      providerErrors = [ ];
    };
  };
}
