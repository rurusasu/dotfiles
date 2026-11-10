{
  inputs,
  homeConfigurations,
}:
{
  testCommonGitAndSshUseTheSharedSignerAndAgent = {
    expr = {
      signer = inputs.nixpkgs.lib.hasSuffix "/bin/op-ssh-sign" homeConfigurations.common.config.programs.git.signing.signer;
      agent = homeConfigurations.common.config.home.sessionVariables.SSH_AUTH_SOCK;
    };
    expected = {
      signer = true;
      agent = "${homeConfigurations.common.config.home.homeDirectory}/.1password/agent.sock";
    };
  };
}
