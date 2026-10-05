require("oil").setup({
    default_file_explorer = true,
    delete_to_trash = true,
    view_options = {
        show_hidden = true,
    },
    keymaps = {
        ["<CR>"] = "actions.select",
        ["<C-s>"] = {
            "actions.select",
            opts = { vertical = true },
        },
        ["<C-h>"] = {
            "actions.select",
            opts = { horizontal = true },
        },
        ["<C-t>"] = {
            "actions.select",
            opts = { tab = true },
        },
        ["<Esc>"] = "actions.close",
        ["g."] = "actions.toggle_hidden",
    },
})

-- Windows のドライブ一覧 (oil:///) は上流でも wmic を使うため、不在時だけ PowerShell で補う。
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

local keys = {
    { "-", "<cmd>Oil<cr>", desc = "Open Oil" },
}

for _, key in ipairs(keys) do
    vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
end
