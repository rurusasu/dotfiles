{ inputs }:
let
  hosts = import ../../hosts { inherit inputs; };
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  inherit (pkgs) lib;
  cfg =
    (hosts.mkNixos {
      system = "x86_64-linux";
      hostPath = ../../hosts/linux.nix;
      configuredUser = "test";
      homeModule = hosts.linuxHome;
      extraModules = [
        {
          nixpkgs.pkgs = pkgs;
          users.users.test.isNormalUser = true;
          home-manager = {
            useGlobalPkgs = true;
            extraSpecialArgs = { inherit inputs; };
            users.test = {
              home = {
                username = "test";
                homeDirectory = "/home/test";
                stateVersion = "25.05";
              };
            };
          };
        }
      ];
    }).config;
  home = cfg.home-manager.users.test;
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
