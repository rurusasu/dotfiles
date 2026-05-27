-- Floating terminal toggle. snacks.terminal の position = "float" が機能しない /
-- vim.fn.termopen() が float window を split に書き換える環境への対策として、
-- 純粋 nvim API + termopen 後に nvim_win_set_config で float 構成を再適用する。
local M = {}

local state = { buf = nil, win = nil }

local function shell_cmd()
    if vim.fn.has("win32") == 1 then
        return "pwsh.exe"
    end
    return vim.o.shell
end

local function float_config()
    local width = math.floor(vim.o.columns * 0.85)
    local height = math.floor(vim.o.lines * 0.85)
    return {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        border = "rounded",
    }
end

function M.toggle()
    -- Already open → hide
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_hide(state.win)
        state.win = nil
        return
    end

    local reuse = state.buf and vim.api.nvim_buf_is_valid(state.buf)
    if not reuse then
        state.buf = vim.api.nvim_create_buf(false, true)
    end

    local cfg = float_config()
    state.win = vim.api.nvim_open_win(state.buf, true, cfg)

    -- Terminal らしく余計な UI を消す (style = "minimal" は環境次第で
    -- nvim_open_win の挙動を変えるため、ここで明示的に off にする)。
    vim.wo[state.win].number = false
    vim.wo[state.win].relativenumber = false
    vim.wo[state.win].signcolumn = "no"
    vim.wo[state.win].cursorline = false

    if not reuse then
        vim.fn.termopen(shell_cmd(), {
            on_exit = function()
                state.buf = nil
                if state.win and vim.api.nvim_win_is_valid(state.win) then
                    pcall(vim.api.nvim_win_close, state.win, true)
                end
                state.win = nil
            end,
        })
        -- termopen が float window を split に変換するケースに備えて
        -- float config を再適用する。
        if state.win and vim.api.nvim_win_is_valid(state.win) then
            pcall(vim.api.nvim_win_set_config, state.win, cfg)
        end
    end

    vim.cmd("startinsert")
end

return M
