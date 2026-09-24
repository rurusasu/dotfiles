{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
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

  testGeminiCliPnpmCatalog = {
    expr = {
      isGlobalPackage = builtins.elem "@google/gemini-cli" sets.windowsOnly.pnpm;
      installArgs = sets.pnpmInstallArgs."@google/gemini-cli";
      verifyCommand = sets.pnpmVerify."@google/gemini-cli";
    };
    expected = {
      isGlobalPackage = true;
      installArgs = [ "--allow-build=@github/keytar" ];
      verifyCommand = {
        command = "gemini";
        args = [ "--version" ];
      };
    };
  };
}
