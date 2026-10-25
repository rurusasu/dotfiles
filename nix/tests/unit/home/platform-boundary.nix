let
  contains =
    needle:
    builtins.any (line: builtins.match ".*${needle}.*" line != null) (
      builtins.filter builtins.isString (builtins.split "\n" (builtins.readFile ../../../home/common.nix))
    );

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
    expr =
      builtins.map
        (
          module:
          builtins.elem (../../../home/common.nix) (
            (module {
              pkgs = { };
              lib = { };
              inputs.nixos-vscode-server.homeModules.default = { };
              config.home.username = "test-user";
            }).imports or [ ]
          )
        )
        [
          (import ../../../home/darwin.nix)
          (import ../../../hosts { inputs = { }; }).linuxHome
          (import ../../../home/wsl.nix)
        ];
    expected = [
      true
      true
      true
    ];
  };
}
