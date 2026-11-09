{ pkgs, fixtures }:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    {
      home.homeDirectory = "/home/test user";
      programs.ssh.enable = true;
    }
  ];
  sshConfig = home.config.home.file.".ssh/config".source;
in
{
  ssh-home-paths = pkgs.runCommand "ssh-home-paths-check" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    ssh -G -F ${sshConfig} github.com > effective-config
    grep -Fx 'identityfile /home/test user/.ssh/signing_key.pub' effective-config
    touch "$out"
  '';
}
