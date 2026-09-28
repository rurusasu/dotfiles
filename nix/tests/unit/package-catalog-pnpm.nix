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
  testPlaywrightInstallUsesSharedBudget = {
    expr = sets.pnpmPostInstall.playwright.timeoutSeconds;
    expected = 3600;
  };

  testDirectInstallersUseSharedBudget = {
    expr = builtins.mapAttrs (_: installer: installer.timeoutSeconds) sets.wingetDirectInstallers;
    expected = {
      bun = 3600;
      chezmoi = 3600;
      direnv = 3600;
      dprint = 3600;
      eza = 3600;
      fd = 3600;
    };
  };

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
        "--allow-build=protobufjs"
        "--allow-build=!node-pty"
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
      installArgs = [
        "--allow-build=@github/keytar"
        "--allow-build=!node-pty"
      ];
      verifyCommand = {
        command = "gemini";
        args = [ "--version" ];
      };
    };
  };
}
