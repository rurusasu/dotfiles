{ pkgs, fixtures }:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    {
      home.homeDirectory = "/home/test user";
      programs.ssh.enable = true;
    }
  ];
  sshConfig = pkgs.writeText "ssh-config" home.config.home.file.".ssh/config".text;
in
{
  ssh-home-paths = pkgs.runCommand "ssh-home-paths-check" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    ssh -G -F ${sshConfig} github.com > effective-config
    grep -Fx 'identityfile /home/test user/.ssh/signing_key.pub' effective-config
    touch "$out"
  '';
}
