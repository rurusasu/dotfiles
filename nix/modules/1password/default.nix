{ lib, ... }: {
  imports = [ ./ssh.nix ];

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
