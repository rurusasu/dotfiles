{ lib, pkgs, ... }: {
  config = lib.mkIf (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
    programs.steam.enable = true;
  };
}
