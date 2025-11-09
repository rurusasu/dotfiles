-- Neovim configuration for VSCode integration and native use
-- Location: ~/.config/nvim/init.lua

-- Leader keys
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

-- Basic settings that work everywhere
vim.opt.clipboard = 'unnamedplus'  -- System clipboard integration
vim.opt.ignorecase = true          -- Case-insensitive search
vim.opt.smartcase = true           -- Case-sensitive if uppercase in search
vim.opt.hlsearch = true            -- Highlight search results
vim.opt.incsearch = true           -- Incremental search

-- Conditional configuration based on VSCode or native Neovim
if vim.g.vscode then
    -- ========================================
    -- VSCode Neovim Configuration
    -- ========================================

    -- Load VSCode-specific settings
    require('vscode-config')

else
    -- ========================================
    -- Native Neovim Configuration
    -- ========================================

    -- UI settings
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.signcolumn = 'yes'
    vim.opt.cursorline = true

    -- Indentation
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
    vim.opt.expandtab = true
    vim.opt.smartindent = true

    -- Scrolling
    vim.opt.scrolloff = 8
    vim.opt.sidescrolloff = 8

    -- Native Neovim-specific plugins and LSP would go here
    -- require('plugins')
    -- require('lsp')
end
