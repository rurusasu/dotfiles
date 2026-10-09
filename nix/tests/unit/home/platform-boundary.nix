let
  common = builtins.readFile ../../../home/common.nix;
  contains =
    needle:
    builtins.any (line: builtins.match ".*${needle}.*" line != null) (
      builtins.filter builtins.isString (builtins.split "\n" common)
    );

  osEntrypoints = [
    ../../../hosts/aarch64-darwin/home.nix
    ../../../hosts/shared/linux-home.nix
    ../../../hosts/x86_64-linux/wsl/home.nix
  ];
  moduleImports =
    path:
    (import path {
      pkgs = { };
      lib = { };
      inputs = { };
      config.home.username = "test-user";
    }).imports or [ ];
  importsCommon = path: builtins.elem (../../../home/common.nix) (moduleImports path);
in
{
  testSharedGitAndSshDoNotDeclareOSSpecificProgramsOrAgents = {
    expr = {
      signer =
        builtins.hasAttr "signer"
          (import ../../../modules/git {
            config = { };
            lib = { };
            pkgs = { };
          }).programs.git.signing;
      agent =
        builtins.hasAttr "extraOptionOverrides"
          (import ../../../modules/ssh.nix {
            pkgs = { };
          }).programs.ssh;
    };
    expected = {
      signer = false;
      agent = false;
    };
  };

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
    expr = builtins.map importsCommon osEntrypoints;
    expected = [
      true
      true
      true
    ];
  };
}
