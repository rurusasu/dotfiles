{
  users.knownUsers = [ "muse" ];
  users.users.muse = {
    uid = 550;
    home = "/Users/muse";
    createHome = true;
    shell = "/bin/zsh";
  };

  environment.etc."ssh/muse-authorized-keys".text = ''
    restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJts3D7OY+PV6fv7p2g+HsTGnlOHhJWjpM6OVvamKtNh hatch
  '';

  services.openssh = {
    enable = true;
    extraConfig = ''
      AllowUsers muse@100.64.0.0/10 muse@fd7a:115c:a1e0::/48
      AuthenticationMethods publickey
      AuthorizedKeysFile none
      # The key file is a nix-darwin symlink into the Nix store.
      AuthorizedKeysCommand /bin/cat /etc/ssh/muse-authorized-keys
      AuthorizedKeysCommandUser muse
    '';
  };
}
