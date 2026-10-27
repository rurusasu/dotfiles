{ inputs }:
let
  home = (import ../../../../fixtures/packages.nix { inherit inputs; }).mkHome "x86_64-linux" [
    ((import ../../../../fixtures/packages.nix { inherit inputs; }).homeModule "wsl")
  ];
in
{
  testNRTShellAliasUsesNixOSRebuildHelper = {
    expr = home.config.programs.zsh.shellAliases.nrt;
    expected = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
  };

  testNRBShellAliasUsesNixOSRebuildHelper = {
    expr = home.config.programs.zsh.shellAliases.nrb;
    expected = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
  };
}
