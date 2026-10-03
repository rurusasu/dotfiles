-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    local opts = {
        colors = {
            copy = "#f9e2af",
            delete = "#f38ba8",
            insert = "#89dceb",
            visual = "#cba6f7",
        },
        line_opacity = {
            copy = 0.4,
            delete = 0.4,
            insert = 0.4,
            visual = 0.4,
        },
    }

    require("modes").setup(opts)
end

return M
