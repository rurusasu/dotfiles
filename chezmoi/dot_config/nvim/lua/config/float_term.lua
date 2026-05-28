-- Floating terminal toggle + dynamic resize.
-- snacks.terminal の position = "float" が機能しない / vim.fn.termopen() が
-- float window を split に書き換える環境への対策として、純粋 nvim API +
-- termopen 後に nvim_win_set_config で float 構成を再適用する。
-- 寸法は lua/config/window_styles.lua の共通 SSOT を参照し、現セッション中の
-- ratio 上書きはモジュール local state に保持する (toggle hide でも維持される)。
local styles = require("config.window_styles")

local M = {}

-- state.ratio が nil の間は styles.float.width に追従する。
local state = { buf = nil, win = nil, ratio = nil }

local STEP = 0.05
local MIN_RATIO = 0.3
local MAX_RATIO = 0.98

local ratio_path = vim.fn.stdpath("data") .. "/nvim_float_term_ratio.json"

local function load_ratio()
    local ok, lines = pcall(vim.fn.readfile, ratio_path)
    if not ok or #lines == 0 then
        return
    end
    local ok2, saved = pcall(vim.fn.json_decode, lines[1])
    if ok2 and saved and type(saved.ratio) == "number" then
        state.ratio = saved.ratio
    end
end

local function save_ratio()
    pcall(vim.fn.writefile, { vim.fn.json_encode({ ratio = state.ratio }) }, ratio_path)
end

local function shell_cmd()
    if vim.fn.has("win32") == 1 then
        return "pwsh.exe"
    end
    return vim.o.shell
end

local function current_ratio()
    return state.ratio or styles.float.width
end

local function float_config()
    local r = current_ratio()
    local width = math.floor(vim.o.columns * r)
    local height = math.floor(vim.o.lines * r)
    return {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        border = styles.float.border,
    }
end

local function apply_size()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        pcall(vim.api.nvim_win_set_config, state.win, float_config())
    end
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

function M.grow()
    state.ratio = math.min(current_ratio() + STEP, MAX_RATIO)
    apply_size()
    save_ratio()
end

function M.shrink()
    state.ratio = math.max(current_ratio() - STEP, MIN_RATIO)
    apply_size()
    save_ratio()
end

function M.reset()
    state.ratio = nil
    apply_size()
    save_ratio()
end

-- 端末リサイズ時に開いている float terminal を新しい画面寸法に合わせる。
-- nvim_win_set_config では emulator に古い border が残り続けるため、
-- window を一度閉じて再オープンすることで完全に消す。
-- terminal mode で作業中なら resize 後も terminal mode に戻す。
vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("FloatTermResize", { clear = true }),
    callback = function()
        if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
            return
        end
        local was_in_terminal = vim.api.nvim_get_mode().mode == "t"
        vim.schedule(function()
            if state.win and vim.api.nvim_win_is_valid(state.win) then
                pcall(vim.api.nvim_win_close, state.win, true)
                state.win = nil
            end
            if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
                return
            end
            state.win = vim.api.nvim_open_win(state.buf, true, float_config())
            vim.wo[state.win].number = false
            vim.wo[state.win].relativenumber = false
            vim.wo[state.win].signcolumn = "no"
            vim.wo[state.win].cursorline = false
            if was_in_terminal then
                vim.cmd("startinsert")
            end
        end)
    end,
})

load_ratio()

return M
