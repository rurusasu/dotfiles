-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    local opts = {
        default_file_explorer = true,
        delete_to_trash = true,
        view_options = { show_hidden = true },
        win_options = {
            conceallevel = 3,
            concealcursor = "nvic",
        },
        watch_for_changes = true,
        keymaps = {
            ["\\"] = { "actions.select", opts = { vertical = true }, desc = "Open vsplit" },
            ["|"] = { "actions.select", opts = { vertical = true }, desc = "Open vsplit" },
            ["s"] = { "actions.select", opts = { horizontal = true }, desc = "Open hsplit" },
            ["t"] = { "actions.select", opts = { tab = true }, desc = "Open in new tab" },
            ["<C-h>"] = false,
            ["<C-l>"] = false,
            ["<Esc>"] = "actions.close",
        },
    }

    require("oil").setup(opts)
    -- Avoid the former FocusGained refresh/select race (PR #263).
    -- <C-l> is reserved for window navigation; refresh manually with
    -- :lua require("oil.actions").refresh.callback() when needed.

    -- wmic was removed in Windows 11; patch drive listing to use PowerShell.
    if vim.fn.has("win32") == 1 and vim.fn.executable("wmic") == 0 then
        local files = require("oil.adapters.files")
        local cache = require("oil.cache")
        local util = require("oil.util")
        local orig = files.list
        files.list = function(url, column_defs, cb)
            local _, path = util.parse_url(url)
            if path ~= "/" then
                return orig(url, column_defs, cb)
            end
            local stdout = ""
            local jid = vim.fn.jobstart({
                "powershell.exe",
                "-NoProfile",
                "-Command",
                "Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name + ':' }",
            }, {
                stdout_buffered = true,
                on_stdout = function(_, data)
                    stdout = table.concat(data, "\n")
                end,
                on_exit = function(_, code)
                    if code ~= 0 then
                        return cb("Error listing windows devices")
                    end
                    local entries = {}
                    for _, line in ipairs(vim.split(stdout, "\n", { trimempty = true })) do
                        local drive = line:match("^(%a+):?%s*$")
                        if drive then
                            table.insert(entries, cache.create_entry(url, drive, "directory"))
                        end
                    end
                    cb(nil, entries)
                end,
            })
            if jid <= 0 then
                cb("Could not list windows devices")
            end
        end
    end

    for _, key in ipairs({ { "-", "<cmd>Oil<cr>", desc = "Open parent directory" } }) do
        vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
    end
end

return M
