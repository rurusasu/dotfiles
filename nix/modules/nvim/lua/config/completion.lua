local M = {}

function M.setup()
    vim.opt.completeopt = { "menu", "menuone", "noselect", "popup" }
    -- Keep native buffer (<C-n>) and filename (<C-x><C-f>) completion.
    vim.keymap.set("i", "<C-Space>", vim.lsp.completion.get, { desc = "LSP completion" })
    vim.keymap.set("i", "<CR>", function()
        if vim.fn.pumvisible() == 1 then
            return vim.fn.complete_info({ "selected" }).selected >= 0 and "<C-y>" or "<C-e><CR>"
        end
        return "<CR>"
    end, { expr = true, desc = "Accept selected completion or newline" })
    for key, direction in pairs({ ["<Tab>"] = 1, ["<S-Tab>"] = -1 }) do
        vim.keymap.set({ "i", "s" }, key, function()
            if vim.fn.pumvisible() == 1 then
                return direction == 1 and "<C-n>" or "<C-p>"
            end
            if vim.snippet.active({ direction = direction }) then
                vim.schedule(function()
                    vim.snippet.jump(direction)
                end)
                return ""
            end
            return key
        end, { expr = true, desc = "Completion or snippet navigation" })
    end
end

return M
