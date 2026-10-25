{ inputs, ... }:
{
  imports = [ inputs.nixos-vscode-server.homeModules.default ];
  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };
}
