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
  testMicrosoftWslHasWindowsOnlyWingetSupport = {
    expr = {
      windowsOnlyWinget = builtins.elem "Microsoft.WSL" sets.windowsOnly.winget;
      support = sets.windowsOnlySupport."Microsoft.WSL";
    };
    expected = {
      windowsOnlyWinget = true;
      support = {
        windows = {
          provider = "winget";
          source = "winget";
          identity = "Microsoft.WSL";
        };
        darwin = {
          unsupported = "Windows subsystem component";
        };
        linux = {
          unsupported = "Windows subsystem component";
        };
      };
    };
  };
}
