-- Neovim configuration
-- Managed by chezmoi

-- Windows: prepend real Python to PATH so Mason (pip/pypi installs) bypass
-- the App Execution Alias stub in WindowsApps.
if vim.fn.has("win32") == 1 then
    local py = vim.fn.expand("$LOCALAPPDATA") .. "\\Programs\\Python\\Python313"
    vim.env.PATH = py .. "\\Scripts;" .. py .. ";" .. vim.env.PATH
end

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- Leader key (before lazy)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load core settings
require("config.options")
require("config.keymaps")
require("config.osc7").setup()

-- Load plugins
require("lazy").setup("plugins", {
    defaults = { lazy = true },
    install = { colorscheme = { "kanagawa" } },
    checker = { enabled = false },
    performance = {
        rtp = {
            disabled_plugins = {
                "gzip",
                "tarPlugin",
                "tohtml",
                "tutor",
                "zipPlugin",
            },
        },
    },
})
