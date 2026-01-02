{ ... }:
{
  programs.git = {
    enable = true;
    userName = "Kohei Miki";
    userEmail = "rurusasu@gmail.com";
    signing = {
      key = "~/.ssh/signing_key.pub";
      signByDefault = true;
    };
    extraConfig = {
      safe.directory = "*";
      core = {
        editor = "nvim";
        sshCommand = "ssh";
      };
      gpg = {
        format = "ssh";
      };
      credential = {
        "https://github.com" = {
          helper = "!/usr/bin/gh auth git-credential";
        };
        "https://gist.github.com" = {
          helper = "!/usr/bin/gh auth git-credential";
        };
      };
    };
  };
}
