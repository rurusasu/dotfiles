# User → Home Manager module mapping for native Linux host.
# Imported by nix/flakes/hosts.nix as home-manager.users.
let
  bootstrapUser = builtins.getEnv "DOTFILES_USER";
  user = if bootstrapUser == "" then "nixos" else bootstrapUser;
in
{
  ${user} =
    { ... }:
    {
      imports = [ ../common.nix ];

      # Native NixOS must preserve the machine hardware profile, so route the
      # shortcut through the same guarded one-command installer.
      programs.zsh.shellAliases = {
        nrs = "~/.dotfiles/install.sh";
      };
    };
}
