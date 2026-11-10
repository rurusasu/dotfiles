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

}
