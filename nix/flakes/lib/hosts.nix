{ inputs }:
{
  mkNixos =
    {
      system,
      hostPath,
      siteLib,
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
      ] ++ extraModules;
    };
}
