# User configuration shared by integrated and standalone Home Manager.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  settings = import ./settings.nix;
  nixSettings = import ../modules/nix/settings.nix;
  nixPackage = pkgs.lixPackageSets.stable.lix;
in
{
  imports = [
    ../modules
    inputs.catppuccin.homeModules.catppuccin
  ];
  catppuccin = {
    enable = true;
    autoEnable = false;
    flavor = "mocha";
  };
  home = {
    username = lib.mkIf (!config.submoduleSupport.enable) (lib.mkDefault settings.username);
    homeDirectory = lib.mkIf (!config.submoduleSupport.enable) (
      lib.mkDefault (
        (if pkgs.stdenv.hostPlatform.isDarwin then "/Users/" else "/home/") + config.home.username
      )
    );
    stateVersion = lib.mkDefault inputs.self.lib.stateVersions.home;
    preferXdgDirectories = true;
    sessionPath = [
      (config.home.homeDirectory + "/.bun/bin")
      (config.home.homeDirectory + "/.local/bin")
      (config.home.homeDirectory + "/bin")
      (config.home.homeDirectory + "/.local/npm/bin")
    ];
    packages = lib.optional (!config.submoduleSupport.enable) config.nix.package;
  };
  xdg.enable = true;
  programs.home-manager.enable = true;
  nix = {
    package = lib.mkDefault nixPackage;
    settings = lib.mkIf (!config.submoduleSupport.enable) nixSettings;
    gc = {
      automatic = !config.submoduleSupport.enable;
      options = "--delete-old";
      dates = "daily";
    };
  };
}
