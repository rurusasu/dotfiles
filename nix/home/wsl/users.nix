# User → Home Manager module mapping for WSL host.
# Imported by nix/flakes/lib/hosts.nix as home-manager.users.
{
  nixos =
    { ... }:
    {
      imports = [ ../common.nix ];
    };
}
