# Custom packages and generated configuration outputs.
# Application installation is owned by modules/.
_: {
  perSystem =
    { pkgs, lib, ... }:
    {
      packages = {
        keybindings-json = (pkgs.formats.json { }).generate "keybindings.json" (
          import ./home/keybindings/bindings.nix { inherit lib; }
        );
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
