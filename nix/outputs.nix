# Custom package output. Application installation is owned by modules/.
_: {
  perSystem =
    { pkgs, lib, ... }:
    {
      packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        darwin-dia-browser = import ./modules/browsers/dia {
          pkgs = import pkgs.path {
            system = pkgs.stdenv.hostPlatform.system;
            config.allowUnfree = true;
          };
        };
      };
    };
}
