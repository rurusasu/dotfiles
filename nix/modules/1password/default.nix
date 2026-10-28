{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.dotfiles.onePassword = {
    enable = lib.mkEnableOption "1Password CLI and desktop SSH integration";
    account = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
      example = "my.1password.com";
      description = "1Password account used by host integrations.";
    };
    ssh.publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFMpL8l17Y0Lci3Y0ZsgnUz75XiHUrQn5vC6XyHZp7wC";
      description = "SSH public key used for authentication and Git signing. When null, leave the public key file unmanaged.";
    };
  };
  config = lib.mkIf config.dotfiles.onePassword.enable {
    home.packages = [ pkgs._1password-cli ];
  };
}
