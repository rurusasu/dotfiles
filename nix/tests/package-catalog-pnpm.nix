{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testDeepSeekHarnessPnpmCatalog = {
    expr = {
      isGlobalPackage = builtins.elem "@deepseek-ai/dsh" sets.pnpmGlobal;
      installArgs = sets.pnpmInstallArgs."@deepseek-ai/dsh";
      verifyCommand = sets.pnpmVerify."@deepseek-ai/dsh";
    };
    expected = {
      isGlobalPackage = true;
      installArgs = [
        "--allow-build=@deepseek-ai/dsh-subprocess-local"
        "--allow-build=@google/genai"
        "--allow-build=koffi"
        "--allow-build=node-pty"
        "--allow-build=protobufjs"
      ];
      verifyCommand = {
        command = "dsh";
        args = [ "--version" ];
      };
    };
  };
}
