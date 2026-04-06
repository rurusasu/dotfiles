# User → Home Manager module mapping for WSL host.
# Imported by nix/flakes/lib/hosts.nix as home-manager.users.
{
  nixos =
    { pkgs, ... }:
    {
      imports = [ ../packages.nix ];

      home.username = "nixos";
      home.homeDirectory = "/home/nixos";
      home.stateVersion = "25.05";

      programs.home-manager.enable = true;
    };
}
