-- Uses already-installed upstream configs and real language servers, without lazy.nvim.
-- DOTFILES_NVIM_LSPCONFIG selects an explicit checkout for CI or local testing.
local root = vim.fn.getcwd() .. "/chezmoi/dot_config/nvim"
local upstream = assert(vim.env.DOTFILES_NVIM_LSPCONFIG, "set DOTFILES_NVIM_LSPCONFIG")
local ts_server = vim.env.DOTFILES_NVIM_TS_SERVER or "tsc"
assert(ts_server == "tsc" or ts_server == "ts_ls")
vim.opt.rtp:prepend(upstream)
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/after")
vim.cmd("filetype plugin indent on")
require("config.completion").setup()
local lsp = require("config.lsp")
for name in pairs(lsp.servers) do
    if name ~= "ty" and name ~= "ruff" and name ~= "tsc" and name ~= "ts_ls" then
        lsp.servers[name] = nil
    end
end
lsp.setup()
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".py")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "answer=42", "print(answer)" })
vim.bo.filetype = "python"
assert(
    vim.wait(15000, function()
        local clients = vim.lsp.get_clients({ bufnr = buf })
        local names = {}
        for _, client in ipairs(clients) do
            if client.initialized then
                names[client.name] = true
            end
        end
        return names.ty and names.ruff
    end, 50),
    "real ty and ruff must attach"
)
local ruff = vim.lsp.get_clients({ bufnr = buf, name = "ruff" })[1]
assert(ruff.server_capabilities.hoverProvider == false)
assert(vim.fn.maparg("<C-y>", "i") == "")
assert(vim.fn.maparg("grr", "n") ~= "", "native references mapping must remain")
assert(
    vim.wait(5000, function()
        return ruff:supports_method("textDocument/formatting", buf)
    end, 20),
    "Ruff must register formatting"
)
vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf })
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "answer = 42", "Ruff save formatting must run")
local tsbuf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(tsbuf)
vim.api.nvim_buf_set_name(tsbuf, vim.fn.tempname() .. ".ts")
vim.api.nvim_buf_set_lines(tsbuf, 0, -1, false, { "const answer: number = 42;", "answer." })
vim.bo.filetype = "typescript"
assert(
    vim.wait(15000, function()
        local clients = vim.lsp.get_clients({ bufnr = tsbuf, name = ts_server })
        return clients[1] and clients[1].initialized
    end, 50),
    "selected TypeScript LSP must attach: " .. ts_server
)
local other_server = ts_server == "tsc" and "ts_ls" or "tsc"
assert(#vim.lsp.get_clients({ bufnr = tsbuf, name = other_server }) == 0, "TypeScript servers must not attach twice")
local tsclient = vim.lsp.get_clients({ bufnr = tsbuf, name = ts_server })[1]
local result = assert(tsclient:request_sync("textDocument/completion", {
    textDocument = { uri = vim.uri_from_bufnr(tsbuf) },
    position = { line = 1, character = 7 },
}, 10000, tsbuf))
assert(not result.err and result.result, "TypeScript completion request must succeed")
local items = result.result.items or result.result
assert(#items > 0, "TypeScript LSP must return actual completion items")
for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop()
end
-- tsc 7.0.2 currently reports exit 1 even with upstream-only configuration.
-- Do not hide that warning: this test proves requests and termination, not a
-- zero server exit code. See docs/chezmoi/neovim.md for the isolated probe.
assert(
    vim.wait(5000, function()
        return #vim.lsp.get_clients() == 0
    end, 20),
    "language servers must shut down"
)
print("Real ty/ruff formatting and " .. ts_server .. " attach/completion passed")
