{ inputs }:
let
  home = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      inherit inputs;
    };
    modules = [
      {
        home.username = "test-user";
        home.homeDirectory = "/home/test-user";
      }
      (import ../../../default.nix { }).homeModules.wsl
    ];
  };
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
