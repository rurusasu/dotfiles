{ lib, ... }: {
  imports = [ ../modules/1password ];

  dotfiles.onePassword.account = lib.mkDefault "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
  dotfiles.onePassword.ssh.publicKey = lib.mkDefault "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFMpL8l17Y0Lci3Y0ZsgnUz75XiHUrQn5vC6XyHZp7wC";
}
