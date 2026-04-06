{ inputs }:
{
  mkNixos =
    {
      system,
      hostPath,
      siteLib,
      homeModulePath ? null,
      extraModules ? [ ],
      overlays ? [ ],
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs siteLib system; };
      modules = [
        hostPath
        (_: { nixpkgs.overlays = overlays; })
        ../../modules/host
      ]
      ++ (
        if homeModulePath != null then
          [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users = import homeModulePath;
            }
          ]
        else
          [ ]
      )
      ++ extraModules;
    };
}
