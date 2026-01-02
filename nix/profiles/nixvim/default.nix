{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraConfigLua = builtins.readFile ./init.lua;
  };
}
