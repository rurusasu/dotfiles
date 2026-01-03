{ pkgs, ... }:
{
  programs.fd = {
    enable = true;
    package = pkgs.fd;
    hidden = true;
    ignores = [
      ".git/"
      "node_modules/"
      "target/"
      "__pycache__/"
      ".cache/"
      ".nix-profile/"
      ".local/share/"
      ".npm/"
      ".cargo/"
    ];
    extraOptions = [
      "--follow"
      "--no-ignore-vcs"
      "--max-results=1000"
      "--max-depth=5"
    ];
  };
}
