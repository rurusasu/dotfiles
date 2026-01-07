{ inputs, ... }:
{
  imports = [
    ../../modules/host
    ../../modules/wsl
    ../../profiles/hosts/k3s
    ./configuration.nix
    inputs.nixos-vscode-server.nixosModules.default
  ];
}
