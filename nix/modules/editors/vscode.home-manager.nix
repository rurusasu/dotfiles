{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.nixos-vscode-server.homeModules.default ];
  config = lib.mkIf config.services.vscode-server.enable {
    services.vscode-server = {
      installPath = [
        "$HOME/.vscode-server"
        "$HOME/.vscode-server-insiders"
      ];
    };
  };
}
