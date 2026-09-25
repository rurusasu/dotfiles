{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      installFeatures = [ ];
    };
    modules = [
      {
        home.username = "test-user";
        home.homeDirectory = "/home/test-user";
      }
      ../../home/wsl.nix
    ];
  };
in
{
  testNRTShellAliasUsesNixOSRebuildHelper = {
    expr = home.config.programs.zsh.shellAliases.nrt;
    expected = "~/.dotfiles/scripts/sh/nixos-rebuild-with-user.sh test --flake ~/.dotfiles --impure";
  };

  testNRBShellAliasUsesNixOSRebuildHelper = {
    expr = home.config.programs.zsh.shellAliases.nrb;
    expected = "~/.dotfiles/scripts/sh/nixos-rebuild-with-user.sh boot --flake ~/.dotfiles --impure";
  };
}
