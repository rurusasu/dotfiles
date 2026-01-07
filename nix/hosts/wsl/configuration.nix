{ pkgs, ... }:
{
  wsl.enable = true;
  wsl.defaultUser = "nixos";

  # Keep this at the first install release unless you know why.
  system.stateVersion = "25.05";

  # Unmount /Docker/host before k3s starts to avoid kubelet issues.
  mySettings.wsl.dockerDesktopIntegration = true;

  users.users.nixos.shell = pkgs.zsh;

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
      "$HOME/.cursor-server"
    ];
  };
}
