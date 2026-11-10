{ fixtures, homeConfigurations }:
let
  inherit (homeConfigurations) wsl;
in
{
  testOnePasswordExplicitlyUnmanagedPublicKeyPreservesExistingFile = {
    expr =
      let
        home = fixtures.mkHome "x86_64-linux" [
          {
            dotfiles.onePassword.enable = true;
            dotfiles.onePassword.ssh.publicKey = null;
          }
        ];
      in
      {
        managesPublicKey = home.config.home.file ? ".ssh/signing_key.pub";
      };
    expected = {
      managesPublicKey = false;
    };
  };
  testOnePasswordSshUsesConfiguredPublicKey = {
    expr =
      map
        (
          system:
          let
            home = fixtures.mkHome system [
              {
                programs.ssh.enable = true;
                dotfiles.onePassword = {
                  enable = true;
                  account = "fixture-account";
                  ssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEPvjJr6iWYXFDo0foUBxas3qR9rJm1hix7E1Z6iY4RM fixture";
                };
              }
            ];
          in
          {
            publicKey = home.config.home.file.".ssh/signing_key.pub".text;
            replaceExistingKey = home.config.home.file.".ssh/signing_key.pub".force;
            executable = home.config.home.file.".ssh/signing_key.pub".executable;
          }
        )
        [
          "x86_64-linux"
          "aarch64-darwin"
        ];
    expected =
      map
        (_: {
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEPvjJr6iWYXFDo0foUBxas3qR9rJm1hix7E1Z6iY4RM fixture\n";
          replaceExistingKey = true;
          executable = false;
        })
        [
          "x86_64-linux"
          "aarch64-darwin"
        ];
  };
  testOnePasswordGitSshPlatformIntegration = {
    expr = map (home: {
      signer = home.config.programs.git.signing.signer;
      agent = home.config.programs.ssh.extraOptionOverrides.IdentityAgent;
      agentEnvironment = home.config.home.sessionVariables.SSH_AUTH_SOCK;
      sshAgentRendered =
        homeConfigurations.lib.hasInfix
          (builtins.unsafeDiscardStringContext "IdentityAgent ${home.config.programs.ssh.extraOptionOverrides.IdentityAgent}")
          home.config.home.file.".ssh/config".text;
      opensshAgentEnabled = home.config.services.ssh-agent.enable;
      gpgSshAgentEnabled = home.config.services.gpg-agent.enableSshSupport;
      publicKeyIsStoreManaged = home.config.home.file ? ".ssh/signing_key.pub";
    }) homeConfigurations.homes;
    expected =
      map
        ({ signer, agentSocket }: {
          inherit signer;
          agent = ''"${agentSocket}"'';
          agentEnvironment = agentSocket;
          sshAgentRendered = true;
          opensshAgentEnabled = false;
          gpgSshAgentEnabled = false;
          publicKeyIsStoreManaged = true;
        })
        [
          {
            signer = "${homeConfigurations.linux.pkgs._1password-gui}/bin/op-ssh-sign";
            agentSocket = "${homeConfigurations.linux.config.home.homeDirectory}/.1password/agent.sock";
          }
          {
            signer = "${wsl.config.home.homeDirectory}/.local/bin/op-ssh-sign-wsl";
            agentSocket = "${wsl.config.home.homeDirectory}/.1password/agent.sock";
          }
          {
            signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
            agentSocket = "${homeConfigurations.darwin.config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
          }
        ];
  };
}
