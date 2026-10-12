{ lib, ... }:
{
  programs.git.settings.ghq.root = lib.mkDefault "~/ghq";
}
