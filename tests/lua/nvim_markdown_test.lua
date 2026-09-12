-- Run with: nvim --headless -u NONE -i NONE -l tests/lua/nvim_markdown_test.lua
local root = vim.fn.getcwd() .. "/chezmoi/dot_config/nvim"
vim.opt.rtp:prepend(root)

local specs = dofile(root .. "/lua/plugins/markdown.lua")
assert(#specs == 1, "Markdown rendering must have one plugin specification")
local spec = specs[1]
assert(spec[1] == "MeanderingProgrammer/render-markdown.nvim", "render-markdown.nvim must be configured")
assert(spec.ft == "markdown", "Markdown rendering must load only for Markdown buffers")
assert(type(spec.opts) == "table", "render-markdown.nvim must use lazy.nvim opts")
assert(
    spec.dependencies and spec.dependencies[1] == "nvim-tree/nvim-web-devicons",
    "Markdown icons dependency must be declared"
)

local markdown_key = spec.keys and spec.keys[1]
assert(markdown_key and markdown_key[1] == "<leader>mp", "<leader>mp must toggle Markdown rendering")
assert(type(markdown_key[2]) == "function", "Markdown toggle must lazy-load the plugin through a function mapping")

vim.g.mapleader = " "
dofile(root .. "/lua/config/keymaps.lua")
local marp_key = vim.fn.maparg("<leader>marp", "n", false, true)
assert(marp_key.desc == "Toggle Marp preview", "<leader>marp must remain the Marp preview mapping")
assert(vim.fn.maparg("<leader>mp", "n") == "", "<leader>mp must not be claimed by Marp")

print("Markdown rendering and Marp keymap checks passed")
