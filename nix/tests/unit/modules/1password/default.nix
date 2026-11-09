{ fixtures, homeConfigurations }:
let
  inherit (homeConfigurations)
    wsl
    ;

in
{
  testDisabledOnePasswordRemovesDarwinDesktopIntegration = {
    expr =
      let
        home = fixtures.mkHome "aarch64-darwin" [
          (fixtures.homeModule "darwin")
          ({ lib, ... }: { dotfiles.onePassword.enable = lib.mkForce false; })
        ];
      in
      {
        guiInstalled = builtins.elem home.pkgs._1password-gui home.config.home.packages;
        managesPublicKey = home.config.home.file ? ".ssh/signing_key.pub";
        configuresAgent = home.config.home.sessionVariables ? SSH_AUTH_SOCK;
        launchdAgent = home.config.launchd.agents ? onepassword-ssh-environment;
        biometricUnlock = home.config.home.sessionVariables ? OP_BIOMETRIC_UNLOCK_ENABLED;
        signer = home.config.programs.git.signing.signer;
      };
    expected = {
      guiInstalled = false;
      managesPublicKey = false;
      configuresAgent = false;
      launchdAgent = false;
      biometricUnlock = false;
      signer = "${homeConfigurations.darwin.pkgs.openssh}/bin/ssh-keygen";
    };
  };

  testWslOnePasswordInstallsNativeCli = {
    expr = {
      nativeCliInstalled = builtins.any (
        package: (package.pname or "") == "1password-cli"
      ) wsl.config.home.packages;
    };
    expected = {
      nativeCliInstalled = true;
    };
  };

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
