{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  user = config.wsl.defaultUser;
  repository = config.users.users.${user}.home + "/.dotfiles";
  fontDirectory = "/usr/local/share/fonts/dotfiles-wslg";
  sshPublicKey = config.home-manager.users.${user}.dotfiles.onePassword.ssh.publicKey;
in
{
  imports = [
    ../linux
    inputs.nixos-wsl.nixosModules.wsl
  ];
  system.activationScripts.wslgFonts = lib.mkIf config.dotfiles.fonts.enable {
    deps = [ "specialfs" ];
    text = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 ${fontDirectory}
      ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Regular.ttf ${fontDirectory}/UDEVGothicNF-Regular.ttf
      ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Bold.ttf ${fontDirectory}/UDEVGothicNF-Bold.ttf
      ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf ${fontDirectory}/NotoColorEmoji.ttf
    '';
  };
  assertions = [
    {
      assertion = builtins.substring 0 1 repository == "/" && !(lib.hasInfix "*" repository);
      message = "WSL Git trust requires one absolute checkout path without wildcards.";
    }
  ];
  # Home Manager starts the keyring; PAM unlocks it at login.
  security.pam.services.login.enableGnomeKeyring = true;
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ user ];
    };
  };
  users.users.${user}.openssh.authorizedKeys.keys = lib.optional (sshPublicKey != null) sshPublicKey;
  wsl = {
    enable = true;
    defaultUser = lib.mkDefault "nixos";
    useWindowsDriver = true;
    wslConf.network.generateHosts = false;
  };
  i18n.extraLocales = [ "ja_JP.UTF-8/UTF-8" ];
  programs = {
    git = {
      enable = true;
      config.safe.directory = [ repository ];
    };
    dconf.enable = true;
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        wayland
        libxkbcommon
      ];
    };
  };
  systemd.user.services.nixos-activation = {
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
  };
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };
}
