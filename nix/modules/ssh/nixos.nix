{ config, lib, ... }:
let
  user = config.wsl.defaultUser;
  home = config.home-manager.users.${user};
  ownerPublicKey = home.dotfiles.onePassword.ssh.publicKey;
in
{
  assertions = [
    {
      assertion = user != "muse";
      message = "The WSL default user must differ from the dedicated Muse SSH account.";
    }
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [
        user
        "muse@100.64.0.0/10"
        "muse@fd7a:115c:a1e0::/48"
      ];
    };
    extraConfig = lib.mkAfter ''
      Match User muse
        AuthenticationMethods publickey
        AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
    '';
  };

  users.users = lib.mkMerge [
    { ${user}.openssh.authorizedKeys.keys = lib.optional (ownerPublicKey != null) ownerPublicKey; }
    {
      muse = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ "restrict ${home.dotfiles.ssh.muse.publicKey}" ];
      };
    }
  ];
}
