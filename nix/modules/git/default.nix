{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.programs.git.enable {
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
        credential = lib.genAttrs [ "https://github.com" "https://gist.github.com" ] (_: {
          helper = "!gh auth git-credential";
        });
      };
    };
  };
}
