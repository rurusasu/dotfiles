# Nixvim plugins - import all plugin configurations
{
  imports = [
    ./treesitter
    ./telescope
    ./lualine
    ./nvim-tree
    ./gitsigns
    ./indent-blankline
    ./nvim-autopairs
    ./nvim-surround
    ./which-key
    ./comment
    ./web-devicons
  ];
}
