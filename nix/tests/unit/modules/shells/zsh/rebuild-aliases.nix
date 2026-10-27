{ fixtures }:
let
  home = fixtures.mkHome "x86_64-linux" [
    (fixtures.homeModule "wsl")
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
