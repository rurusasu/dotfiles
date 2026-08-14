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
      homeExtraSpecialArgs ? { },
    }:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs siteLib system; };
      modules = [
        { nixpkgs.hostPlatform = system; }
        hostPath
        { nixpkgs.overlays = overlays; }
        ../../modules/host
      ]
      ++ (
        if homeModulePath != null then
          [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit inputs;
                  isWSL = false;
                }
                // homeExtraSpecialArgs;
                users = import homeModulePath;
              };
            }
          ]
        else
          [ ]
      )
      ++ extraModules;
    };
}
