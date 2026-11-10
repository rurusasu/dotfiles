-- Run after loading the Home Manager-generated init.lua and native plugins.
assert(vim.v.errmsg == "", "plugin startup must not report errors: " .. vim.v.errmsg)
vim.cmd.colorscheme("catppuccin")
assert(
    vim.v.errmsg == "" and vim.api.nvim_get_hl(0, { name = "RainbowRed" }).fg == 0xE06C75,
    "colorscheme reload must preserve plugin highlights without errors: " .. vim.v.errmsg
)

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

local markdown_key = vim.fn.maparg("<leader>mp", "n", false, true)
markdown_key.callback()
markdown_key.callback()

-- Preview a directory without package.json using the Nix-provided Marp server.
local slides = vim.fn.tempname() .. "/slides with spaces"
vim.fn.mkdir(slides, "p")
local deck = slides .. "/deck.md"
vim.fn.writefile({ "---", "marp: true", "---", "# Marp Nix preview" }, deck)
vim.api.nvim_buf_set_name(buf, deck)
local open = vim.ui.open
local preview_url
vim.ui.open = function(url)
    preview_url = url
end
vim.cmd("MarpPreview")
local ready = vim.wait(15000, function()
    return preview_url ~= nil
end, 20)
local response
if ready then
    response = vim.system({ "curl", "--fail", "--silent", preview_url .. "deck.md" }):wait(5000)
end
vim.cmd("MarpStop")
vim.ui.open = open
assert(ready, "Marp must become ready and open the browser")
assert(preview_url == "http://localhost:18765/", "Marp must use the configured port")
assert(response.code == 0 and response.stdout:find("Marp Nix preview", 1, true), "Marp must render the slide")
assert(response.stdout:find('data-theme="gaia"', 1, true), "Marp must apply the Nix-managed theme")
assert(
    vim.wait(5000, function()
        return vim.system({ "curl", "--fail", "--silent", "--max-time", "1", preview_url }):wait().code ~= 0
    end, 20),
    "MarpStop must stop the server"
)
vim.fn.delete(vim.fs.dirname(slides), "rf")
assert(vim.fn.maparg("<leader>as", "n") ~= "", "Sidekick mapping must remain available")
for _, direction in ipairs({ "h", "j", "k", "l" }) do
    local key = "<C-" .. direction .. ">"
    assert(vim.fn.maparg(key, "n") == "<C-W>" .. direction, "normal navigation must use native windows")
    local terminal_key = vim.fn.maparg(key, "t")
    assert(terminal_key:sub(-6) == "<C-W>" .. direction, "terminal navigation must use native windows")
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# Heading", "", "```python", "answer = 42", "```" })
vim.bo.filetype = "markdown"
assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "Markdown highlighting must start")

local sidekick_config = require("sidekick.config")
assert(sidekick_config.cli.win.wo.wrap, "Sidekick CLI terminal must wrap long lines")

-- termopen() resets 'wrap'; the Sidekick config must re-apply it after start.
local sidekick_term = {
    buf = vim.api.nvim_create_buf(false, true),
    group = vim.api.nvim_create_augroup("TestSidekickWrap", { clear = true }),
}
sidekick_config.cli.win.config(sidekick_term)
vim.cmd("vsplit")
sidekick_term.win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(sidekick_term.win, sidekick_term.buf)
vim.fn.jobstart({ "sh", "-c", "printf x" }, { term = true })
assert(
    vim.wait(1000, function()
        return vim.wo[sidekick_term.win].wrap
    end, 20),
    "Sidekick terminal must re-apply 'wrap' after termopen"
)

-- The Sidekick scrollback uses nvim_open_term(), which also resets 'wrap'.
local scrollback = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(sidekick_term.win, scrollback)
local scrollback_chan = vim.api.nvim_open_term(scrollback, {})
assert(
    vim.wait(1000, function()
        return vim.wo[sidekick_term.win].wrap
    end, 20),
    "Sidekick scrollback must keep 'wrap' after nvim_open_term"
)
pcall(vim.fn.chanclose, scrollback_chan)
vim.api.nvim_win_set_buf(sidekick_term.win, sidekick_term.buf)
vim.api.nvim_win_close(sidekick_term.win, true)
vim.api.nvim_buf_delete(sidekick_term.buf, { force = true })
vim.api.nvim_buf_delete(scrollback, { force = true })

print("Markdown rendering and Marp preview checks passed")
