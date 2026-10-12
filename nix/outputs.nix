# Standalone artifacts. Application installation is owned by modules/.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      packages = {
        windows-keybindings-export = import ./hosts/windows/export.nix { inherit pkgs lib; };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        darwin-dia-browser = import ./modules/browsers/dia {
          pkgs = import pkgs.path {
            system = pkgs.stdenv.hostPlatform.system;
            config.allowUnfree = true;
          };
        };
      };
    };
}
