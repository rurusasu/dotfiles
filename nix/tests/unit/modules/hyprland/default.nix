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
        (code.nix.defaults inputs).systemDefaults
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
}
