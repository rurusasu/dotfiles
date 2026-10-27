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
  onlyEnableFlags =
    tree:
    builtins.all (
      name:
      if name == "enable" then
        builtins.isBool tree.${name}
      else
        builtins.isAttrs tree.${name} && onlyEnableFlags tree.${name}
    ) (builtins.attrNames tree);
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
      programs = onlyEnableFlags common.programs;
      services = onlyEnableFlags common.services;
      agents = common ? launchd;
      sessionVariables = common.home ? sessionVariables;
      sessionPath = common.home ? sessionPath;
    };
    expected = {
      programs = true;
      services = true;
      agents = false;
      sessionVariables = false;
      sessionPath = false;
    };
  };
}
