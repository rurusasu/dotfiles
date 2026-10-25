let
  defaults = import ../../../default.nix { };
  common = defaults.homeModules.common {
    config = { };
    lib.mkDefault = value: value;
    pkgs = { };
  };
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
  testCommonHomeModuleDoesNotRequireOSSpecialArgs = {
    expr = builtins.attrNames (builtins.functionArgs defaults.homeModules.common);
    expected = [
      "config"
      "lib"
      "pkgs"
    ];
  };
  testCommonHomeKeepsPlatformPathsAndEnvironmentInOsModules = {
    expr = {
      homebrewPath = builtins.elem "/opt/homebrew/bin" common.home.sessionPath;
      variables = builtins.attrNames (common.home.sessionVariables or { });
      darwin = common ? targets;
      wsl = common ? systemd;
      signer = common.programs.git.signing.signer or null;
    };
    expected = {
      homebrewPath = false;
      variables = [ ];
      darwin = false;
      wsl = false;
      signer = null;
    };
  };
}
