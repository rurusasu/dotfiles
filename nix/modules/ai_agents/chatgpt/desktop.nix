# Selected by native NixOS; common.nix also serves WSL and owns configuration.
{ inputs, pkgs, ... }:
let
  packages = import ./packages.nix { inherit inputs pkgs; };
in
{
  # Use upstream's cleanup policy for the writable bundled-plugin cache.
  xdg.configFile."user-tmpfiles.d/chatgpt.conf".source =
    "${packages.chatgpt}/share/user-tmpfiles.d/chatgpt.conf";
}
