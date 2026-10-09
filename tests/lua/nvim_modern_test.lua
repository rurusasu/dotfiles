-- Run with: nvim --headless -u NONE -l tests/lua/nvim_modern_test.lua
local root = vim.fn.getcwd() .. "/nix/modules/editors/nvim"
vim.opt.rtp:prepend(root)

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

-- Formatter settings are applied by the shared LSP setup without personal overrides.
assert(vim.lsp.config.nixd.settings.nixd.formatting.command[1] == "nixfmt")
assert(vim.lsp.config.nixd.settings.nixd.options == nil, "personal NixOS completion must not be configured")
assert(vim.lsp.config.yamlls.settings.yaml.format.enable)
assert(vim.lsp.config.gopls.settings.gopls.gofumpt)

-- Exercise the save handler with attached-client doubles, without external servers.
-- Nix/Lua must format too; unsupported buffers must remain untouched.
local get_clients, format = vim.lsp.get_clients, vim.lsp.buf.format
local clients, calls = {}, {}
vim.lsp.get_clients = function(opts)
    if opts and opts.method == "textDocument/formatting" then
        return clients
    end
    return get_clients(opts)
end
vim.lsp.buf.format = function(opts)
    calls[#calls + 1] = opts
end
local buf = vim.api.nvim_get_current_buf()
local function save_as(filetype, name)
    vim.cmd("noautocmd setlocal filetype=" .. filetype)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. name)
    calls = {}
    vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf, group = "DotfilesLsp" })
end
clients = { { id = 7, name = "nixd" } }
save_as("nix", ".nix")
assert(#calls == 1 and calls[1].id == 7, "Nix must format automatically on save")
assert(calls[1].bufnr == buf and calls[1].timeout_ms == 3000 and not calls[1].async)
clients = { { id = 8, name = "lua_ls" } }
save_as("lua", "") -- filetype, not an extension glob, controls formatting
assert(#calls == 1 and calls[1].id == 8, "extensionless Lua buffer must format")
clients = { { id = 3, name = "ty" }, { id = 9, name = "ruff" } }
save_as("python", ".py")
assert(#calls == 1 and calls[1].id == 9, "Python must use only Ruff")
clients = { { id = 3, name = "ty" } }
save_as("python", ".py")
assert(#calls == 0, "Python must not fall back to a second formatter when Ruff is absent")
clients = { { id = 8, name = "other" }, { id = 2, name = "formatter" } }
save_as("typescript", ".ts")
assert(#calls == 1 and calls[1].id == 2, "multiple providers must not format twice")
clients = {}
save_as("text", ".txt")
assert(#calls == 0, "buffers without a formatter must not trigger formatting")
clients = { { id = 7, name = "nixd" } }
vim.bo.buftype = "nofile"
save_as("nix", ".nix")
assert(#calls == 0, "special buffers must not be formatted")
vim.bo.buftype = ""
vim.bo.modifiable = false
save_as("nix", ".nix")
assert(#calls == 0, "nonmodifiable buffers must not be formatted")
vim.bo.modifiable = true
vim.lsp.get_clients, vim.lsp.buf.format = get_clients, format

-- Re-running setup must not accumulate format/attach handlers.
lsp.setup()
assert(#vim.api.nvim_get_autocmds({ group = "DotfilesLsp", event = "LspAttach" }) == 1)
assert(#vim.api.nvim_get_autocmds({ group = "DotfilesLsp", event = "BufWritePre" }) == 1)
for name in pairs(lsp.servers) do
    vim.lsp.enable(name, false)
end
print("Neovim native configuration checks passed")
