vim.lsp.enable("powershell_es")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".ps1")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Get-Chil" })
vim.bo.filetype = "ps1"
assert(
    vim.wait(30000, function()
        local clients = vim.lsp.get_clients({ bufnr = buf, name = "powershell_es" })
        return clients[1] and clients[1].initialized
    end, 50),
    "PowerShell Editor Services must attach"
)
local client = vim.lsp.get_clients({ bufnr = buf, name = "powershell_es" })[1]
local result = assert(client:request_sync("textDocument/completion", {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = 0, character = 8 },
}, 10000, buf))
assert(not result.err and result.result, "PowerShell completion must succeed")
assert(#(result.result.items or result.result) > 0, "PowerShell completion must return candidates")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "if($true){Write-Output 'value'}" })
assert(
    vim.wait(5000, function()
        return client:supports_method("textDocument/formatting", buf)
    end, 20),
    "PowerShell must register formatting"
)
vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf })
assert(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= "if($true){Write-Output 'value'}",
    "PowerShell save formatting must run: " .. vim.inspect(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
)
client:stop()
assert(
    vim.wait(5000, function()
        return #vim.lsp.get_clients({ name = "powershell_es" }) == 0
    end, 20),
    "PowerShell Editor Services must shut down"
)
print("PowerShell attach, completion and save formatting passed")
