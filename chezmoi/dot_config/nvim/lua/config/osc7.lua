local M = {}

local function emit_osc7(path)
    if not path or path == "" then
        return
    end

    -- vim.uri_from_fname handles spaces and Windows paths safely.
    local uri = vim.uri_from_fname(path)
    io.write(string.format("\27]7;%s\27\\", uri))
    io.flush()
end

function M.sync_cwd_to_terminal()
    if vim.bo.filetype == "oil" then
        local ok, oil = pcall(require, "oil")
        if ok then
            local oil_dir = oil.get_current_dir()
            if oil_dir and oil_dir ~= "" then
                emit_osc7(oil_dir)
                return
            end
        end
    end

    emit_osc7(vim.fn.getcwd())
end

function M.setup()
    local group = vim.api.nvim_create_augroup("DotfilesOsc7", { clear = true })
    vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "BufEnter" }, {
        group = group,
        callback = M.sync_cwd_to_terminal,
    })
end

return M
