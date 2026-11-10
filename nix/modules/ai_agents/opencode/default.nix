{ pkgs, ... }: {
  programs.opencode = {
    enable = true;
    package = import ./package.nix { inherit pkgs; };
  };
}
