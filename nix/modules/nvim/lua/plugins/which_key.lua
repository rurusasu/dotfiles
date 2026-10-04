-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    local opts = {}

    require("which-key").setup(opts)
end

return M
