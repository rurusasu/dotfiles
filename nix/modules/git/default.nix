{
  config,
  pkgs,
  lib,
  platform,
  ...
}:
{
  imports = [
    ./ghq
    ./gwq
  ];
  config = lib.mkMerge [
    { programs.git.enable = true; }
    (lib.mkIf config.programs.git.enable {
      home.packages = [ pkgs.gh ];
      programs.git.signing.signer = lib.mkIf config.dotfiles.onePassword.enable (
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${config.dotfiles.onePassword.darwinAppPath}/Contents/MacOS/op-ssh-sign"
        else if platform == "wsl" then
          config.home.homeDirectory + "/.local/bin/op-ssh-sign-wsl"
        else
          "${pkgs._1password-gui}/bin/op-ssh-sign"
      );

      programs.git = {
        signing = {
          format = "ssh";
          key = config.home.homeDirectory + "/.ssh/signing_key.pub";
          signByDefault = false;
        };

        settings = {
          user = {
            name = "rurusasu";
            email = "36875744+rurusasu@users.noreply.github.com";
          };
          core = {
            editor = "nvim";
            sshCommand = "ssh";
          };
          # Keep links readable by both Windows Git and WSL Git on a shared drive.
          worktree.useRelativePaths = true;
          url."git@github.com:".insteadOf = "https://github.com/";
          credential = lib.genAttrs [ "https://github.com" "https://gist.github.com" ] (_: {
            helper = "!gh auth git-credential";
          });
        };
      };
    })
  ];
}
