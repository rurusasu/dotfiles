local M = {}

-- Parser binaries and matching queries may be supplied by the Nix wrapper.
-- Other installations can place them under stdpath('data')/site.
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
    local runtime = vim.env.DOTFILES_NVIM_TREESITTER
    if runtime and runtime ~= "" then
        vim.opt.rtp:prepend(runtime)
    end
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("DotfilesTreesitter", { clear = true }),
        callback = function(args)
            M.start(args.buf)
        end,
    })
end

return M
