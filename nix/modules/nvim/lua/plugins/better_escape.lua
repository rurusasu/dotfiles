-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    local opts = {
        timeout = 100,
        default_mappings = false,
        mappings = {
            i = { j = { k = "<ESC>" } },
            t = { j = { k = "<C-\\><C-n>" } },
        },
    }

    require("better_escape").setup(opts)
end

return M
