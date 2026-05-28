-- Floating terminal toggle + dynamic resize.
-- snacks.terminal の position = "float" が機能しない / vim.fn.termopen() が
-- float window を split に書き換える環境への対策として、純粋 nvim API +
-- termopen 後に nvim_win_set_config で float 構成を再適用する。
-- 寸法は lua/config/window_styles.lua の共通 SSOT を参照し、現セッション中の
-- ratio 上書きはモジュール local state に保持する (toggle hide でも維持される)。
-- id ごとに buf/win を分けて持つことで、shell / lazygit など複数の float
-- terminal を独立に toggle できる。ratio は全 id 共通 (ユーザの体感上は
-- 「float の大きさ」は一つで良い)。
local styles = require("config.window_styles")

local M = {}

-- Instances keyed by id. ratio は全インスタンスで共有する。
local instances = {}
local ratio = nil

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
        ratio = saved.ratio
    end
end

local function save_ratio()
    pcall(vim.fn.writefile, { vim.fn.json_encode({ ratio = ratio }) }, ratio_path)
end

local function default_shell()
    if vim.fn.has("win32") == 1 then
        return "pwsh.exe"
    end
    return vim.o.shell
end

local function current_ratio()
    return ratio or styles.float.width
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

local function get(id)
    instances[id] = instances[id] or { buf = nil, win = nil }
    return instances[id]
end

local function apply_window_options(win)
    -- style = "minimal" は環境次第で nvim_open_win の挙動を変えるため、
    -- ここで明示的に off にする。
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].cursorline = false
end

local function apply_size()
    for _, inst in pairs(instances) do
        if inst.win and vim.api.nvim_win_is_valid(inst.win) then
            pcall(vim.api.nvim_win_set_config, inst.win, float_config())
        end
    end
end

---@class config.FloatTerm.ToggleOpts
---@field id? string                  instance id (default "shell")
---@field cmd? string | string[]      command to run (default shell)
---@field cwd? string                 working directory
---@field env? table<string, string>  extra env vars (merged with parent env)

---@param opts? config.FloatTerm.ToggleOpts
function M.toggle(opts)
    opts = opts or {}
    local id = opts.id or "shell"
    local cmd = opts.cmd or default_shell()
    local cwd = opts.cwd
    local env = opts.env
    local inst = get(id)

    -- Already open → hide (buf は保持して次回再表示で resume できるように)。
    if inst.win and vim.api.nvim_win_is_valid(inst.win) then
        vim.api.nvim_win_hide(inst.win)
        inst.win = nil
        return
    end

    -- cwd / cmd / env が前回と違う場合は古い buffer を捨てて新規に作り直す。
    -- 例: repo A で lazygit を開いて hide → repo B に移動して再 toggle、を
    -- そのまま reuse すると A の lazygit プロセスが見えてしまう。
    if
        inst.buf
        and vim.api.nvim_buf_is_valid(inst.buf)
        and (not vim.deep_equal(inst.cmd, cmd) or inst.cwd ~= cwd or not vim.deep_equal(inst.env, env))
    then
        pcall(vim.api.nvim_buf_delete, inst.buf, { force = true })
        inst.buf = nil
    end

    local reuse = inst.buf and vim.api.nvim_buf_is_valid(inst.buf)
    if not reuse then
        inst.buf = vim.api.nvim_create_buf(false, true)
        inst.cmd = cmd
        inst.cwd = cwd
        inst.env = env
    end

    local cfg = float_config()
    inst.win = vim.api.nvim_open_win(inst.buf, true, cfg)
    apply_window_options(inst.win)

    if not reuse then
        vim.fn.termopen(cmd, {
            cwd = cwd,
            env = env,
            on_exit = function()
                inst.buf = nil
                inst.cmd = nil
                inst.cwd = nil
                inst.env = nil
                if inst.win and vim.api.nvim_win_is_valid(inst.win) then
                    pcall(vim.api.nvim_win_close, inst.win, true)
                end
                inst.win = nil
            end,
        })
        -- termopen が float window を split に変換するケースに備えて
        -- float config を再適用する。
        if inst.win and vim.api.nvim_win_is_valid(inst.win) then
            pcall(vim.api.nvim_win_set_config, inst.win, cfg)
        end
    end

    vim.cmd("startinsert")
end

function M.grow()
    ratio = math.min(current_ratio() + STEP, MAX_RATIO)
    apply_size()
    save_ratio()
end

function M.shrink()
    ratio = math.max(current_ratio() - STEP, MIN_RATIO)
    apply_size()
    save_ratio()
end

function M.reset()
    ratio = nil
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
        local visible = {}
        for id, inst in pairs(instances) do
            if inst.win and vim.api.nvim_win_is_valid(inst.win) then
                visible[#visible + 1] = id
            end
        end
        if #visible == 0 then
            return
        end
        local was_in_terminal = vim.api.nvim_get_mode().mode == "t"
        vim.schedule(function()
            for _, id in ipairs(visible) do
                local inst = instances[id]
                if inst and inst.win and vim.api.nvim_win_is_valid(inst.win) then
                    pcall(vim.api.nvim_win_close, inst.win, true)
                    inst.win = nil
                end
                if inst and inst.buf and vim.api.nvim_buf_is_valid(inst.buf) then
                    inst.win = vim.api.nvim_open_win(inst.buf, true, float_config())
                    apply_window_options(inst.win)
                end
            end
            if was_in_terminal then
                vim.cmd("startinsert")
            end
        end)
    end,
})

load_ratio()

return M
