# User → Home Manager module mapping for native Linux host.
# Imported by nix/flakes/hosts.nix as home-manager.users.
{
  nixos =
    { ... }:
    {
      imports = [ ../common.nix ];
    };
}
