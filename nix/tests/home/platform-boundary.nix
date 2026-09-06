let
  common = builtins.readFile ../../home/common.nix;
  contains =
    needle:
    builtins.any (line: builtins.match ".*${needle}.*" line != null) (
      builtins.filter builtins.isString (builtins.split "\n" common)
    );

  osEntrypoints = [
    ../../home/darwin.nix
    ../../home/linux.nix
    ../../home/wsl.nix
  ];
  hasCommonImport =
    path:
    builtins.any (line: builtins.match ".*imports.*common[.]nix.*" line != null) (
      builtins.filter builtins.isString (builtins.split "\n" (builtins.readFile path))
    );
in
{
  testCommonHomeModuleDoesNotRequireWSLSpecialArg = {
    expr = contains "isWSL";
    expected = false;
  };

  testCommonHomeModuleDoesNotContainDarwinBranch = {
    expr = contains "isDarwin";
    expected = false;
  };

  testCommonHomeModuleDoesNotContainDarwinPath = {
    expr = contains "/opt/homebrew";
    expected = false;
  };

  testCommonHomeModuleDoesNotContainDarwinEnvironment = {
    expr =
      contains "HOMEBREW_AUTO_UPDATE_SECS"
      || contains "OP_BIOMETRIC_UNLOCK_ENABLED"
      || contains "TERMINFO_DIRS";
    expected = false;
  };

  testOSHomeEntrypointsKeepCommonImport = {
    expr = builtins.map hasCommonImport osEntrypoints;
    expected = [
      true
      true
      true
    ];
  };
}
