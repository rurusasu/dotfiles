{
  config,
  inputs,
  pkgs,
  ...
}:
let
  configuredUser = builtins.getEnv "DOTFILES_USER";
  configuredHome = builtins.getEnv "DOTFILES_HOME";
  configuredGroup = builtins.getEnv "DOTFILES_GROUP";
  user = if configuredUser == "" then "nixos" else configuredUser;
  home = if configuredHome == "" then "/home/${user}" else configuredHome;
  group = if configuredGroup == "" then "users" else configuredGroup;
in
{
  imports = [
    ../../modules/wsl
    ./configuration.nix
    inputs.nixos-vscode-server.nixosModules.default
  ];

  users.groups.${group} = { };
  users.users.${user} = {
    isNormalUser = true;
    inherit home group;
    createHome = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };
}
