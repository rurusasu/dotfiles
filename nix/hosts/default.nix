# Shared OS settings and platform-specific host configuration.
{
  inputs,
  pkgs,
  platform,
  ...
}:
let
  nixSettings = import ../modules/nix/settings.nix;
  nixPackage = pkgs.lixPackageSets.stable.lix;
in
{
  time.timeZone = "Asia/Tokyo";
  nix = {
    package = nixPackage;
    gc = {
      automatic = true;
      options = "--delete-old";
    };
    settings = nixSettings // {
      min-free = 10 * 1024 * 1024 * 1024;
    };
  };
  nixpkgs.config.allowUnfree = true;
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
  };
  home-manager = {
    backupFileExtension = "hm-backup";
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs platform; };
    sharedModules = [ ../home ];
  };
  imports = [
    {
      darwin = ./darwin;
      linux = ./linux;
      wsl = ./wsl;
    }
    .${platform}
  ];
}
