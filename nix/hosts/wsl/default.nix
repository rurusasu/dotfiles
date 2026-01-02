{ config, inputs, pkgs, ... }:
{
  imports = [
    ../../modules/host
    ../../modules/wsl
    ./configuration.nix
    inputs.nixos-vscode-server.nixosModules.default
  ];

  users.users.nixos.shell = pkgs.zsh;

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };
}
