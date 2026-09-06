-- Run with: nvim --headless -u NONE -l tests/lua/nvim_modern_test.lua
local root = vim.fn.getcwd() .. "/chezmoi/dot_config/nvim"
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/after")

local completion = require("config.completion")
completion.setup()
assert(vim.o.completeopt:find("popup"), "completion documentation popup must be enabled")
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

local treesitter = require("config.treesitter")
treesitter.setup()
assert(vim.treesitter.language.get_lang("sh") == "bash")
assert(vim.treesitter.language.get_lang("javascriptreact") == "javascript")
assert(vim.treesitter.language.get_lang("typescriptreact") == "tsx")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local answer = 42" })
vim.bo.filetype = "lua"
assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "builtin Lua highlighting must start")
vim.bo.filetype = "dotfiles_missing_parser"
treesitter.start(vim.api.nvim_get_current_buf()) -- absent parser is a supported fallback
assert(not package.loaded["nvim-treesitter"], "highlighting must not depend on the plugin")

local lsp = require("config.lsp")
local saved_path = vim.env.PATH
vim.env.PATH = ""
lsp.setup()
assert(not vim.lsp.is_enabled("lua_ls"), "missing executables must not be enabled")
assert(not vim.lsp.is_enabled("nixd"), "missing nixd must not be enabled")
vim.env.PATH = saved_path

-- Local per-server overrides are discoverable by the native loader.
assert(vim.lsp.config.lua_ls.settings.Lua.runtime.version == "LuaJIT")
assert(vim.lsp.config.ty.root_markers[1] == "ty.toml")
assert(vim.lsp.config.rust_analyzer.settings["rust-analyzer"].check.command == "clippy")
assert(vim.lsp.config.nixd.cmd[1] == "nixd")

-- Re-running setup must not accumulate format/attach handlers.
lsp.setup()
assert(#vim.api.nvim_get_autocmds({ group = "DotfilesLsp", event = "LspAttach" }) == 1)
assert(#vim.api.nvim_get_autocmds({ group = "DotfilesLsp", event = "BufWritePre" }) == 2)
for name in pairs(lsp.servers) do
    vim.lsp.enable(name, false)
end
print("Neovim native configuration checks passed")
