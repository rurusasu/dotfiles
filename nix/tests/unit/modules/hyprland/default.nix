{
  inputs,
  fixtures,
  code,
}:
let
  pkgs = fixtures.mkPkgs "x86_64-linux";
  home =
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
    }).config.home-manager.users.nixos;
in
{
  testNativeHomeConfiguresTheSystemOwnedHyprlandSession = {
    expr = {
      enabled = home.wayland.windowManager.hyprland.enable;
      format = home.wayland.windowManager.hyprland.configType;
      systemOwnsCompositor = home.wayland.windowManager.hyprland.package == null;
    };
    expected = {
      enabled = true;
      format = "lua";
      systemOwnsCompositor = true;
    };
  };
  testNativeHomeBindsNotesToObsidian = {
    expr =
      let
        binding = builtins.head (
          builtins.filter (
            candidate: builtins.head candidate._args == "SUPER + SHIFT + O"
          ) home.wayland.windowManager.hyprland.settings.bind
        );
      in
      (builtins.elemAt binding._args 1).expr;
    expected = ''hl.dsp.exec_cmd("obsidian")'';
  };
}
