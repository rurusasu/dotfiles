{ inputs }: {
  users,
  siteLib,
  system,
  extraSharedModules ? [],
}: { config, ... }: let
  normalize = spec:
    if builtins.isPath spec || builtins.isString spec
    then (import spec)
    else spec;
  hmUsers = builtins.mapAttrs (_: normalize) users;
in {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs siteLib system;
      systemConfig = config;
      dotfilesPath = "/home/${builtins.elemAt (builtins.attrNames users) 0}/.dotfiles";
    };
    backupFileExtension = "hm-bak";
    users = hmUsers;
    sharedModules = (import ./shared-modules.nix { inherit inputs; }) ++ extraSharedModules;
  };
}
