# Selected with the desktop app on Darwin and native Linux.
{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  # Home Manager owns tmpfiles generation, activation, and systemd integration.
  systemd.user.tmpfiles.rules = lib.optionals pkgs.stdenv.hostPlatform.isLinux (
    lib.splitString "\n" (
      lib.removeSuffix "\n" (
        builtins.readFile "${inputs.chatgpt-nixpkgs}/pkgs/by-name/ch/chatgpt/tmpfiles.conf"
      )
    )
  );
}
