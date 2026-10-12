{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  installed =
    system:
    builtins.any (package: (package.pname or "") == "chatgpt")
      (fixtures.mkHome system [
        ../../home/common.nix
        ../../modules/editors/nvim
      ]).config.home.packages;
in
{
  testChatGPTInstallationIsOwnedByTools = {
    expr = {
      darwin = installed "aarch64-darwin";
      linux = installed "x86_64-linux";
    };
    expected = {
      darwin = true;
      linux = false;
    };
  };
}
