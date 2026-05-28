-- Shared float window dimensions (SSOT).
-- Reference this from any plugin / module that opens a floating window so
-- that resizing happens in one place.
local M = {}

---@class config.WindowStyle.Float
---@field width number   ratio of vim.o.columns (0..1)
---@field height number  ratio of vim.o.lines   (0..1)
---@field border string  vim window border style
M.float = {
    width = 0.85,
    height = 0.85,
    border = "rounded",
}

return M
