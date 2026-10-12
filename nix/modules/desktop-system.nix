# macOS GUI applications belong to the nix-darwin system profile.
{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.aerospace
    (import ./browsers/dia { inherit pkgs; })
    pkgs.google-chrome
    pkgs.obsidian
    pkgs.raycast
    # Host integrations such as Orca need GitHub CLI outside the user profile.
    pkgs.gh
  ];
}
