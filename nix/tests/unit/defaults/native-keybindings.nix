{
  inputs,
  fixtures,
  code,
}:
let
  pkgs = fixtures.mkPkgs "x86_64-linux";
  inherit (pkgs) lib;
  cfg =
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        platform = "linux";
      };
      modules = [
        code.nix.hosts.default
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
      codex = builtins.any (
        path: lib.hasPrefix "${home.programs.chatgpt.package}/" path
      ) home.home.sessionPath;
      aiShortcut = builtins.any (
        binding: (builtins.elemAt binding._args 1).expr == ''hl.dsp.exec_cmd("chatgpt")''
      ) home.wayland.windowManager.hyprland.settings.bind;
      cliManaged = home.programs.codex.enable && home.programs.codex.package == null;
    };
    expected = {
      chatgpt = true;
      codex = true;
      aiShortcut = true;
      cliManaged = true;
    };
  };
  testNativeDesktopModulesSelectTheirPackages = {
    expr = {
      compositor = builtins.elem cfg.programs.hyprland.package cfg.environment.systemPackages;
    };
    expected = {
      compositor = true;
    };
  };
}
