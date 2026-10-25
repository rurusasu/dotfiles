# Host metadata is supplied once by the Windows bootstrap; rebuilds read it here.
{ lib }:
let
  settings =
    if builtins.pathExists /etc/nixos/dotfiles.json then
      builtins.fromJSON (builtins.readFile /etc/nixos/dotfiles.json)
    else
      { };
  persistedUser =
    if builtins.pathExists /var/lib/dotfiles/user then
      lib.removeSuffix "\n" (builtins.readFile /var/lib/dotfiles/user)
    else
      "";
  sudoUser = builtins.getEnv "SUDO_USER";
  currentUser = builtins.getEnv "USER";
  user =
    settings.user or (
      if sudoUser != "" && sudoUser != "root" then
        sudoUser
      else if persistedUser != "" then
        persistedUser
      else if builtins.pathExists /etc/NIXOS && currentUser != "" && currentUser != "root" then
        currentUser
      else
        "nixos"
    );
  account = lib.findFirst (entry: builtins.length entry >= 7 && builtins.head entry == user) null (
    if builtins.pathExists /etc/passwd then
      map (lib.splitString ":") (lib.splitString "\n" (builtins.readFile /etc/passwd))
    else
      [ ]
  );
  gid = settings.gid or (if account == null then "" else builtins.elemAt account 3);
  groupEntry =
    lib.findFirst (entry: builtins.length entry >= 3 && builtins.elemAt entry 2 == gid) null
      (
        if builtins.pathExists /etc/group then
          map (lib.splitString ":") (lib.splitString "\n" (builtins.readFile /etc/group))
        else
          [ ]
      );
  home = settings.home or (if account == null then "/home/${user}" else builtins.elemAt account 5);

in
{
  inherit user home gid;
  uid = settings.uid or (if account == null then "" else builtins.elemAt account 2);
  group = settings.group or (if groupEntry == null then "users" else builtins.head groupEntry);
  repository = settings.repository or "${home}/.dotfiles";
}
