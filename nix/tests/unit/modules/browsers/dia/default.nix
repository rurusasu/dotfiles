{ inputs }:
{
  testCustomDarwinPackagesPreserveVendorBundleDerivationAttributes = {
    expr =
      builtins.mapAttrs
        (_: package: {
          dontFixup = package.dontFixup or false;
          source = toString package.src;
          platforms = package.meta.platforms;
        })
        {
          dia-browser = import ../../../../../modules/browsers/dia/package.nix {
            inherit inputs;
            pkgs = import inputs.nixpkgs {
              system = "aarch64-darwin";
              config.allowUnfree = true;
            };
          };
        };
    expected = {
      dia-browser = {
        dontFixup = true;
        source = toString inputs.dia;
        platforms = [ "aarch64-darwin" ];
      };
    };
  };
}
