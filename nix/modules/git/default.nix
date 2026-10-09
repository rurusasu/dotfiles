{
  config,
  lib,
  ...
}:
{
  imports = [
    ./ghq.nix
    ./gtr.nix
  ];

  programs.git = {
    enable = true;

    signing = {
      format = "ssh";
      key = "~/.ssh/signing_key.pub";
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
      credential = lib.genAttrs [ "https://github.com" "https://gist.github.com" ] (_: {
        helper = "!gh auth git-credential";
      });
    };
  };

  # Git reads both XDG config and ~/.gitconfig. Clear the old higher-priority
  # chezmoi settings without including the XDG file a second time.
  home.file.".gitconfig" = {
    force = true;
    text = ''
      # Managed by Home Manager.
      # Git settings: ${config.xdg.configHome}/git/config
    '';
  };
  xdg.configFile."git/config".force = true;
}
