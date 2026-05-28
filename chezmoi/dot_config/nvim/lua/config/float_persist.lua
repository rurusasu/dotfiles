-- Persist floating window position across sessions.
-- Keys windows by title (snacks windows) or buftype (plain terminal floats).
local M = {}

local path = vim.fn.stdpath("data") .. "/nvim_float_positions.json"

local function read()
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok or #lines == 0 then
        return {}
    end
    local ok2, t = pcall(vim.fn.json_decode, lines[1])
    return (ok2 and type(t) == "table") and t or {}
end

local function write(t)
    pcall(vim.fn.writefile, { vim.fn.json_encode(t) }, path)
end

local function win_key(win)
    if not vim.api.nvim_win_is_valid(win) then
        return nil
    end
    local cfg = vim.api.nvim_win_get_config(win)
    local title = cfg.title
    if type(title) == "string" and title ~= "" then
        return title
    elseif type(title) == "table" and title[1] then
        local t0 = title[1]
        local s = type(t0) == "string" and t0 or (type(t0) == "table" and t0[1] or nil)
        if type(s) == "string" and s ~= "" then
            return s
        end
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" then
        return "terminal"
    end
    local ft = vim.bo[buf].filetype
    return ft ~= "" and ("ft:" .. ft) or nil
end

function M.save(win)
    if not vim.api.nvim_win_is_valid(win) then
        return
    end
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "" then
        return
    end
    local key = win_key(win)
    if not key then
        return
    end
    local t = read()
    t[key] = { row = cfg.row, col = cfg.col, width = cfg.width, height = cfg.height }
    write(t)
end

function M.restore(win)
    if not vim.api.nvim_win_is_valid(win) then
        return
    end
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "" then
        return
    end
    local key = win_key(win)
    if not key then
        return
    end
    local saved = read()[key]
    if not saved then
        return
    end
    local patch = { row = saved.row, col = saved.col }
    if saved.width then
        patch.width = saved.width
    end
    if saved.height then
        patch.height = saved.height
    end
    pcall(vim.api.nvim_win_set_config, win, patch)
end

function M.setup()
    vim.api.nvim_create_autocmd("WinNew", {
        group = vim.api.nvim_create_augroup("FloatPersist", { clear = true }),
        callback = function()
            local win = vim.api.nvim_get_current_win()
            vim.defer_fn(function()
                if not vim.api.nvim_win_is_valid(win) then
                    return
                end
                local cfg = vim.api.nvim_win_get_config(win)
                if cfg.relative == "" then
                    return
                end
                M.restore(win)
            end, 80)
        end,
    })
end

return M
