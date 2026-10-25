{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    linux
    wsl
    darwin
    ;
  expectedIntegration =
    {
      signer,
      agentSocket,
    }:
    {
      inherit signer;
      agent = ''"${agentSocket}"'';
      agentEnvironment = agentSocket;
      opensshAgentEnabled = false;
      gpgSshAgentEnabled = false;
      publicKeyActivationAfter = [ "writeBoundary" ];
      publicKeyIsStoreManaged = false;
    };
in
{
  testOnePasswordGitSshPlatformIntegration = {
    expr = map (home: {
      signer = home.config.programs.git.signing.signer;
      agent = home.config.programs.ssh.extraOptionOverrides.IdentityAgent;
      agentEnvironment = home.config.home.sessionVariables.SSH_AUTH_SOCK;
      opensshAgentEnabled = home.config.services.ssh-agent.enable;
      gpgSshAgentEnabled = home.config.services.gpg-agent.enableSshSupport;
      publicKeyActivationAfter = home.config.home.activation.onePasswordSshPublicKey.after;
      publicKeyIsStoreManaged = home.config.home.file ? ".ssh/signing_key.pub";
    }) homes;
    expected = map expectedIntegration [
      {
        signer = "/opt/1Password/op-ssh-sign";
        agentSocket = "${linux.config.home.homeDirectory}/.1password/agent.sock";
      }
      {
        signer = "${wsl.config.home.homeDirectory}/.local/bin/op-ssh-sign-wsl";
        agentSocket = "${wsl.config.home.homeDirectory}/.1password/agent.sock";
      }
      {
        signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
        agentSocket = "${darwin.config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
      }
    ];
  };
}
