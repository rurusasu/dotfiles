local M = {}

-- Home Manager supplies parser binaries and matching queries as native packages.
function M.start(buf)
    if vim.bo[buf].buftype ~= "" then
        return
    end
    local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
    if not lang or not vim.treesitter.language.add(lang) then
        return -- Native syntax/indent files remain available without a parser.
    end
    vim.treesitter.start(buf, lang)
end

function M.setup()
    vim.treesitter.language.register("bash", "sh")
    vim.treesitter.language.register("javascript", "javascriptreact")
    vim.treesitter.language.register("tsx", "typescriptreact")
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("DotfilesTreesitter", { clear = true }),
        callback = function(args)
            M.start(args.buf)
        end,
    })
end

return M
