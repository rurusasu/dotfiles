{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
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
  testCommonGitAndSshUseTheSharedSignerAndAgent = {
    expr = {
      signer = inputs.nixpkgs.lib.hasSuffix "/bin/ssh-keygen" homeConfigurations.common.config.programs.git.signing.signer;
      agent = homeConfigurations.common.config.home.sessionVariables.SSH_AUTH_SOCK;
    };
    expected = {
      signer = true;
      agent = "${homeConfigurations.common.config.home.homeDirectory}/.1password/agent.sock";
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
