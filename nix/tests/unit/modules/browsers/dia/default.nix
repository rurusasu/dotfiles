{
  inputs,
  fixtures,
  code,
}:
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
          dia-browser = code.nix.modules.browsers.dia.package {
            inherit inputs;
            pkgs = fixtures.mkPkgs "aarch64-darwin";
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
