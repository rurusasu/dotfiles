-- Run with: nvim --headless -u NONE -l nix/tests/build/modules/editors/nvim/modern.lua

assert(vim.fn.maparg("<C-y>", "i") == "", "native completion acceptance must remain available")

-- Exercise expression mappings without depending on a terminal's key encoding.
local enter = vim.fn.maparg("<CR>", "i", false, true).callback
local tab = vim.fn.maparg("<Tab>", "i", false, true).callback
local backtab = vim.fn.maparg("<S-Tab>", "i", false, true).callback
local pumvisible, complete_info = vim.fn.pumvisible, vim.fn.complete_info
vim.fn.pumvisible = function()
    return 1
end
vim.fn.complete_info = function()
    return { selected = -1 }
end
assert(enter() == "<C-e><CR>", "unselected popup must not accept its first item")
vim.fn.complete_info = function()
    return { selected = 0 }
end
assert(enter() == "<C-y>")
assert(tab() == "<C-n>" and backtab() == "<C-p>")
vim.fn.pumvisible = function()
    return 0
end
assert(enter() == "<CR>" and tab() == "<Tab>")
local active, jump = vim.snippet.active, vim.snippet.jump
local jumped
vim.snippet.active = function(opts)
    return opts.direction == -1
end
vim.snippet.jump = function(direction)
    jumped = direction
end
assert(backtab() == "")
assert(
    vim.wait(1000, function()
        return jumped == -1
    end),
    "snippet navigation must execute"
)
vim.fn.pumvisible, vim.fn.complete_info = pumvisible, complete_info
vim.snippet.active, vim.snippet.jump = active, jump

print("Neovim native configuration checks passed")
