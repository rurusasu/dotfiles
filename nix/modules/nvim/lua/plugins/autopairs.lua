-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    local opts = { map_cr = false }

    require("nvim-autopairs").setup(opts)
end

return M
