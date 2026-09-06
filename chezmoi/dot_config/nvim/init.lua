-- Neovim configuration
-- Managed by chezmoi

if vim.fn.has("nvim-0.12") == 0 then
    error("This configuration requires Neovim 0.12 or newer. Update the package before applying it.")
end

-- Leader key (before lazy)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load core settings
require("config.options")
require("config.keymaps")
require("config.osc7").setup()
require("config.completion").setup()

require("config.lazy")
require("config.treesitter").setup()
