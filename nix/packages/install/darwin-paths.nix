# Inventory output paths without realizing optional providers as report inputs.
{ darwinPackages }:
builtins.mapAttrs (
  _: package: builtins.unsafeDiscardStringContext (toString package)
) darwinPackages
