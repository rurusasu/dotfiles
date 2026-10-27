let
  sharedHome =
    builtins.head
      ((import ../../../defaults.nix { }).systemDefaults {
        inputs = { };
        pkgs = { };
        platform = "linux";
      }).home-manager.sharedModules;
  common = sharedHome {
    config = { };
    lib.mkDefault = value: value;
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
    expr = builtins.attrNames (builtins.functionArgs sharedHome);
    expected = [
      "config"
      "lib"
    ];
  };
  testCommonHomeOnlyDeclaresApplicationEnableFlags = {
    expr = {
      programs = builtins.all (
        program: builtins.attrNames program == [ "enable" ] && builtins.isBool program.enable
      ) (builtins.attrValues common.programs);
      inherit (common) services;
      agents = common ? launchd;
      sessionVariables = common.home ? sessionVariables;
      sessionPath = common.home ? sessionPath;
    };
    expected = {
      programs = true;
      services.ollama.enable = true;
      agents = false;
      sessionVariables = false;
      sessionPath = false;
    };
  };
}
