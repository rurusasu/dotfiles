{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      tobiasalthoff.atom-material-theme
      ms-vscode-remote.remote-containers
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-ssh-edit
      hediet.vscode-drawio
      jnoortheen.nix-ide
      arrterian.nix-env-selector
      kamadorueda.alejandra
      vscodevim.vim
      wakatime.vscode-wakatime
    ];
  };

  home.file.".config/Code/User/settings.json".source = ../../../home/config/vscode/settings.json;
  home.file.".config/Code/User/keybindings.json".source = ../../../home/config/vscode/keybindings.json;
}
