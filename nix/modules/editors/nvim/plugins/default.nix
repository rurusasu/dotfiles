{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./catppuccin.nix
    ./gitsigns.nix
    ./incline.nix
    ./indent-blankline.nix
    ./modes.nix
    ./lspconfig.nix
    ./nvim-autopairs.nix
    ./nvim-surround.nix
    ./oil.nix
    ./render-markdown.nix
    ./sidekick.nix
    ./snacks.nix
    ./treesitter.nix
    ./web-devicons.nix
    ./which-key.nix
  ];
  home.packages =
    lib.mkIf config.programs.nixvim.enable
      (pkgs.neovimUtils.makeVimPackageInfo (
        map (
          plugin: if plugin ? plugin then builtins.removeAttrs plugin [ "runtime" ] else plugin
        ) config.programs.nixvim.extraPlugins
      )).runtimeDeps;
}
