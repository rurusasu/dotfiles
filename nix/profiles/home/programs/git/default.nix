{ ... }:
{
  programs.git = {
    enable = true;
    signing = {
      key = "~/.ssh/signing_key.pub";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "Kohei Miki";
        email = "rurusasu@gmail.com";
      };
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
