{ lib, pkgs, ... }: {
  imports = [ ./ssh.nix ];

  config.home.packages = [ pkgs._1password-cli ];

  config.dotfiles.onePassword = {
    account = lib.mkDefault "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
    ssh.publicKey = lib.mkDefault "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFMpL8l17Y0Lci3Y0ZsgnUz75XiHUrQn5vC6XyHZp7wC";
  };

  options.dotfiles.onePassword = {
    account = lib.mkOption {
      type = lib.types.nonEmptyStr;
      example = "my.1password.com";
      description = "1Password account used by host integrations.";
    };

    ssh.publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "SSH public key used for authentication and Git signing. When null, leave the public key file unmanaged.";
    };
  };
}
