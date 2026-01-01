{ inputs }: let
  hmUsers = import ./hm-users.nix { inherit inputs; };
in {
  mkNixos = {
    system,
    hostPath,
    users,
    siteLib,
    extraModules ? [],
    overlays ? [],
  }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs siteLib system; };
      modules =
        [
          hostPath
          (_: { nixpkgs.overlays = overlays; })
          inputs.home-manager.nixosModules.home-manager
          (hmUsers { inherit users siteLib system; })
          ../../modules/host
        ]
        ++ extraModules;
    };
}
