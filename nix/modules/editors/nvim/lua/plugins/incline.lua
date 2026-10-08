local c = {
    fg = "#c0caf5",
    dim = "#565f89",
    error = "#f7768e",
    warn = "#e0af68",
    info = "#7dcfff",
}
local set_hl = function()
    vim.api.nvim_set_hl(0, "InclineActive", { bg = "#2d2f3f", fg = c.fg })
    vim.api.nvim_set_hl(0, "InclineInactive", { bg = "#2d2f3f", fg = c.dim })
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

local devicons = require("nvim-web-devicons")
local generic_set = {}
for _, n in ipairs({
    "init.lua",
    "init.vim",
    "init.ts",
    "init.js",
    "index.ts",
    "index.js",
    "index.tsx",
    "index.jsx",
    "main.rs",
    "main.go",
    "main.py",
    "main.c",
    "main.cpp",
    "mod.rs",
    "lib.rs",
}) do
    generic_set[n] = true
end

require("incline").setup({
    window = {
        padding = 1,
        margin = { horizontal = 1, vertical = 0 },
        placement = { horizontal = "right", vertical = "bottom" },
        winhighlight = {
            active = { Normal = "InclineActive" },
            inactive = { Normal = "InclineInactive" },
        },
        options = { winblend = 0 },
    },
    render = function(props)
        local bufnr = props.buf
        if vim.bo[bufnr].buftype == "terminal" then
            return false
        end
        local focused = props.focused
        local fname = vim.api.nvim_buf_get_name(bufnr)
        local tail = fname ~= "" and vim.fn.fnamemodify(fname, ":t") or "[No Name]"
        local name = tail
        if generic_set[tail] then
            local parent = vim.fn.fnamemodify(fname, ":h:t")
            if parent ~= "" and parent ~= "." then
                name = parent .. "/" .. tail
            end
        end

        local icon, icon_color
        if fname ~= "" then
            icon, icon_color = devicons.get_icon_color(tail, vim.fn.fnamemodify(fname, ":e"), { default = true })
        end
        icon = icon or " "
        icon_color = (focused and icon_color) or c.dim

        local result = {}
        if focused then
            local diag_specs = {
                { vim.diagnostic.severity.ERROR, "⊘", c.error },
                { vim.diagnostic.severity.WARN, "△", c.warn },
                { vim.diagnostic.severity.INFO, "⊙", c.info },
            }
            local any = false
            local counts = vim.diagnostic.count(bufnr)
            for _, spec in ipairs(diag_specs) do
                local count = counts[spec[1]] or 0
                if count > 0 then
                    result[#result + 1] = { spec[2] .. " " .. count .. " ", guifg = spec[3] }
                    any = true
                end
            end
            if any then
                result[#result + 1] = { "| ", guifg = c.dim }
            end
        end

        result[#result + 1] = { icon .. " ", guifg = icon_color }
        result[#result + 1] = { name, guifg = focused and c.fg or c.dim }
        if vim.bo[bufnr].modified then
            result[#result + 1] = { " ●", guifg = c.warn }
        end
        return result
    end,
})
