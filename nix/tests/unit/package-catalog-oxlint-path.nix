{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testOxlintHasNoWindowsPathOrPortableLinkMetadata = {
    expr =
      !(builtins.hasAttr "oxlint" sets.wingetPathEntries)
      && !(builtins.hasAttr "oxc-project.oxlint" sets.wingetPathEntries)
      && !(builtins.hasAttr "oxlint" sets.wingetPortableLinksById)
      && !(builtins.hasAttr "oxc-project.oxlint" sets.wingetPortableLinksById);
    expected = true;
  };
}
