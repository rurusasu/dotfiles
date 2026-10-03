-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    require("catppuccin").setup({
        flavour = "mocha",
        transparent_background = true,
    })
    vim.cmd.colorscheme("catppuccin-mocha")
end

return M
