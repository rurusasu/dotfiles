{ config, lib, ... }:
let
  home = config.home-manager.users.${config.system.primaryUser};
in
{
  programs.gnupg.agent.enableSSHSupport = false;

  users.knownUsers = [ "muse" ];
  users.users.muse = {
    uid = 550;
    home = "/Users/muse";
    createHome = true;
    shell = "/bin/zsh";
  };

  # macOS creates this group when Remote Login is limited to selected users.
  system.activationScripts.users.text = lib.mkAfter ''
    if /usr/bin/dscl . -read /Groups/com.apple.access_ssh RecordName >/dev/null 2>&1 \
      && ! /usr/sbin/dseditgroup -o checkmember -n . -m muse com.apple.access_ssh >/dev/null; then
      /usr/sbin/dseditgroup -o edit -n . -a muse -t user com.apple.access_ssh
    fi
  '';

  environment.etc."ssh/muse-authorized-keys".text = ''
    restrict ${home.dotfiles.ssh.muse.publicKey}
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
