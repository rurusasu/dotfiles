{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  inherit (pkgs) lib;
  cfg =
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        (import ../../default.nix { inherit inputs; }).hostModules.linux
        {
          nixpkgs.pkgs = pkgs;
          users.users.nixos.home = "/srv/nixos";
        }
      ];
    }).config;
  home = cfg.home-manager.users.nixos;
in
{
  testNativeHomeInheritsHostIdentityAndNix = {
    expr = {
      user = home.home.username;
      directory = home.home.homeDirectory;
      nix = home.nix.package == cfg.nix.package;
      globalPackages = cfg.home-manager.useGlobalPkgs;
      userPackages = cfg.home-manager.useUserPackages;
    };
    expected = {
      user = "nixos";
      directory = "/srv/nixos";
      nix = true;
      globalPackages = true;
      userPackages = true;
    };
  };
  testNativeHostSelectsHyprlandUserModule = {
    expr = cfg.programs.hyprland.enable;
    expected = true;
  };
  testNativeHomeInstallsChatGPTAndBundledCodex = {
    expr = {
      chatgpt = builtins.elem "chatgpt" (map lib.getName home.home.packages);
      codex = builtins.elem "codex" (map lib.getName home.home.packages);
      aiShortcut = lib.hasInfix "chatgpt" home.wayland.windowManager.hyprland.extraConfig;
      cliManaged = home.programs.codex.enable && home.programs.codex.package == null;
      cleanup = home.systemd.user.tmpfiles.rules;
    };
    expected = {
      chatgpt = true;
      codex = true;
      aiShortcut = true;
      cliManaged = true;
      cleanup = [ ];
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
