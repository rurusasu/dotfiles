{
  inputs,
  homeConfigurations ? import ../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    wsl
    ;
  fixtures = import ../../../fixtures/packages.nix { inherit inputs; };
in
{
  testWslOnePasswordUsesNativeCliWithoutWindowsForwarder = {
    expr = {
      forwardsToWindows = wsl.config.home.file ? ".local/bin/op";
      nativeCliInstalled = builtins.any (
        package: (package.pname or "") == "1password-cli"
      ) wsl.config.home.packages;
    };
    expected = {
      forwardsToWindows = false;
      nativeCliInstalled = true;
    };
  };

  testOnePasswordExplicitlyUnmanagedPublicKeyPreservesExistingFile = {
    expr =
      let
        home = fixtures.mkHome "x86_64-linux" [
          ../../../../modules/1password
          { dotfiles.onePassword.ssh.publicKey = null; }
        ];
      in
      {
        managesPublicKey = home.config.home.file ? ".ssh/signing_key.pub";
        publicKeyActivation = home.config.home.activation ? onePasswordSshPublicKey;
      };
    expected = {
      managesPublicKey = false;
      publicKeyActivation = false;
    };
  };

  testOnePasswordSshUsesConfiguredPublicKey = {
    expr =
      map
        (
          system:
          let
            home = fixtures.mkHome system [
              ../../../../modules/1password
              {
                programs.ssh.enable = true;
                dotfiles.onePassword = {
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
            publicKeyActivation = home.config.home.activation ? onePasswordSshPublicKey;
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
          publicKeyActivation = false;
        })
        [
          "x86_64-linux"
          "aarch64-darwin"
        ];
  };

  testWslOnePasswordAccountUsesUserConfiguration = {
    expr =
      (homeConfigurations.mkHome {
        system = "x86_64-linux";
        module = {
          imports = [ (fixtures.homeModule "wsl") ];
          dotfiles.onePassword.account = "fixture-wsl-account";
        };
      }).config.home.sessionVariables.OP_ACCOUNT;
    expected = "fixture-wsl-account";
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
      publicKeyActivation = home.config.home.activation ? onePasswordSshPublicKey;
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
          publicKeyActivation = false;
          publicKeyIsStoreManaged = true;
        })
        [
          {
            signer = "/opt/1Password/op-ssh-sign";
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
