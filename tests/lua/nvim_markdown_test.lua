-- Run after loading the Home Manager-generated init.lua and native plugins.
assert(vim.v.errmsg == "", "plugin startup must not report errors: " .. vim.v.errmsg)
assert(package.loaded["config.completion"], "core setup must run before plugin configuration")
assert(package.loaded["config.autocmds"], "editing autocmds must initialize")
assert(vim.o.inccommand == "split" and vim.o.splitkeep == "screen")
assert(vim.o.list and vim.o.confirm and vim.o.autoread)
assert(vim.o.tabstop == 2 and vim.o.shiftwidth == 2 and vim.o.expandtab)

-- Restore a valid last-edit position, but preserve an explicitly chosen position.
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "second", "third" })
vim.api.nvim_buf_set_mark(buf, '"', 2, 3, {})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, group = "DotfilesEditing" })
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 3 }), "last-edit position must be restored")
vim.api.nvim_win_set_cursor(0, { 3, 1 })
vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, group = "DotfilesEditing" })
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 3, 1 }), "explicit cursor position must be preserved")
require("config.autocmds").setup()
assert(#vim.api.nvim_get_autocmds({ group = "DotfilesEditing", event = "BufReadPost" }) == 1)
assert(package.loaded["oil"], "Oil must be ready for directory buffers at startup")
assert(package.loaded["snacks"], "Snacks must initialize before VimEnter")
assert(package.loaded["render-markdown"], "Markdown rendering must be configured")
assert(not package.loaded["lazy"], "Home Manager must manage plugins without lazy.nvim")

local markdown_key = vim.fn.maparg("<leader>mp", "n", false, true)
assert(markdown_key.desc == "Toggle Markdown rendering", "<leader>mp must toggle Markdown rendering")
assert(type(markdown_key.callback) == "function", "Markdown toggle must remain a function mapping")
markdown_key.callback()
markdown_key.callback()

local marp_key = vim.fn.maparg("<leader>marp", "n", false, true)
assert(marp_key.desc == "Toggle Marp preview", "<leader>marp must remain the Marp preview mapping")
assert(vim.fn.maparg("<leader>ff", "n") ~= "", "file picker mapping must remain available")
assert(vim.fn.maparg("<leader>as", "n") ~= "", "Sidekick mapping must remain available")
assert(vim.fn.exists(":DevcontainerUp") == 2, "Devcontainer commands must be configured")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# Heading", "", "```python", "answer = 42", "```" })
vim.bo.filetype = "markdown"
assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "Markdown highlighting must start")
for name in pairs(require("config.lsp").servers) do
    vim.lsp.enable(name, false)
end

print("Markdown rendering and Marp keymap checks passed")
