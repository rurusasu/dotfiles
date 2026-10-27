-- Run with the generated Home Manager init and native plugin pack, in isolated XDG dirs.
local oil = require("oil")
local allocation = require("config.shared_keybindings")
local original_cwd = vim.uv.cwd()
local root = vim.fn.tempname() .. "-keybinding-runtime"
vim.fn.mkdir(root .. "/child", "p")
vim.fn.mkdir(root .. "/destination", "p")
vim.fn.writefile({ "original" }, root .. "/original.txt")
vim.fn.writefile({ "nested" }, root .. "/child/nested.txt")
vim.cmd.cd(root)
vim.o.columns = 160
vim.o.lines = 50
vim.o.clipboard = ""
for name in pairs(require("config.lsp").servers) do
    vim.lsp.enable(name, false)
end

local function wait_for(predicate, message)
    assert(vim.wait(5000, predicate, 10), message)
end

local function press(key)
    local mapping = vim.fn.maparg(key, "n", false, true)
    assert(not vim.tbl_isempty(mapping), "missing runtime mapping: " .. key)
    if mapping.callback then
        mapping.callback()
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "xt", false)
    end
end

local function open_dir(path)
    local complete, error_message = false, nil
    oil.open(path, {}, function(err)
        complete, error_message = true, err
    end)
    wait_for(function()
        return complete and vim.bo.filetype == "oil" and vim.bo.modifiable
    end, "Oil did not finish loading " .. path)
    assert(not error_message, error_message)
end

local function entry(name)
    local found
    wait_for(function()
        for row = 1, vim.api.nvim_buf_line_count(0) do
            local item = oil.get_entry_on_line(0, row)
            if item and item.name == name then
                vim.api.nvim_win_set_cursor(0, { row, 0 })
                found = item
                return true
            end
        end
    end, "missing Oil entry: " .. name)
    return found
end

local function answer(value, action)
    local original = vim.ui.input
    vim.ui.input = function(_, callback)
        callback(value)
    end
    local ok, err = pcall(action)
    vim.ui.input = original
    assert(ok, err)
end

local function confirm()
    wait_for(function()
        return vim.bo.filetype == "oil_preview"
    end, "Oil mutation must show its confirmation window")
    press("y")
    wait_for(function()
        return vim.bo.filetype == "oil" and vim.bo.modifiable
    end, "Oil mutation did not finish")
end

local trigger = false
for _, item in ipairs(require("which-key.config").options.triggers) do
    trigger = trigger or item[1] == "<leader>"
end
assert(trigger, "Space must trigger which-key")

-- Launch the real file pickers and Lazygit with disposable config/repository state.
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
for _, key in ipairs({ "<leader><leader>", "<leader>sg" }) do
    press(key)
    wait_for(function()
        return #Snacks.picker.get() == 1
    end, key .. " must open a file picker")
    Snacks.picker.get()[1]:close()
    wait_for(function()
        return #Snacks.picker.get() == 0
    end, "picker must close")
    vim.cmd.stopinsert()
end
press("<leader>gg")
wait_for(function()
    return _G.__snacks_last_lg and vim.api.nvim_buf_is_valid(_G.__snacks_last_lg.buf)
end, "Space g g must launch Lazygit")
local terminal = _G.__snacks_last_lg
local job = vim.b[terminal.buf].terminal_job_id
assert(job and vim.fn.jobwait({ job }, 0)[1] == -1, "Lazygit process must be running")
-- Terminate only this probe's child; suppress its expected forced-exit notification.
vim.api.nvim_clear_autocmds({ event = "TermClose", group = terminal.augroup, buffer = terminal.buf })
vim.fn.jobstop(job)
terminal:close()
vim.cmd.stopinsert()

-- Real sidebar behavior: files open in the editor; directories remain in the sidebar.
vim.cmd.edit(root .. "/original.txt")
local editor = vim.api.nvim_get_current_win()
press("<leader>e")
wait_for(function()
    return vim.bo.filetype == "oil" and vim.bo.modifiable
end, "Space e must open Oil")
local sidebar = vim.api.nvim_get_current_win()
assert(sidebar ~= editor and vim.w.dotfiles_oil_sidebar)
local width = vim.api.nvim_win_get_width(sidebar)
press("<C-Right>")
assert(vim.api.nvim_win_get_width(sidebar) == width + 2)
press("<C-Left>")
assert(vim.api.nvim_win_get_width(sidebar) == width)
press("<C-w>w")
assert(vim.api.nvim_get_current_win() == editor)
press("<C-Right>")
assert(vim.api.nvim_win_get_width(sidebar) == width + 2, "resize from editor must target sidebar")
vim.api.nvim_set_current_win(sidebar)
entry("child")
press("<CR>")
wait_for(function()
    return oil.get_current_dir() == root .. "/child/" and vim.bo.modifiable
end, "directory selection must navigate in sidebar")
assert(vim.api.nvim_get_current_win() == sidebar and vim.w.dotfiles_oil_sidebar)
entry("nested.txt")
press("<CR>")
wait_for(function()
    return vim.api.nvim_get_current_win() == editor
end, "file selection must return focus to editor")
assert(vim.api.nvim_buf_get_name(0) == root .. "/child/nested.txt")
assert(vim.bo[vim.api.nvim_win_get_buf(sidebar)].filetype == "oil")
press("<leader>e")
assert(not vim.api.nvim_win_is_valid(sidebar), "Space e must close sidebar from editor")

-- Normal buffer keys operate on real, named buffers.
vim.cmd.edit(root .. "/original.txt")
local previous = vim.api.nvim_get_current_buf()
vim.cmd.edit(root .. "/child/nested.txt")
local current = vim.api.nvim_get_current_buf()
press("<S-h>")
assert(vim.api.nvim_get_current_buf() == previous, "Shift h must select previous buffer")
press("<S-l>")
assert(vim.api.nvim_get_current_buf() == current, "Shift l must select next buffer")
press("<leader>bd")
assert(not vim.bo[current].buflisted, "Space b d must remove current buffer")

-- All six Oil keys are buffer local and use actual Oil save/confirmation/mutation paths.
open_dir(root)
for _, binding in ipairs(allocation.bindings) do
    if binding.scope == "oil" then
        assert(vim.fn.maparg(binding.key, binding.mode, false, true).buffer == 1, binding.action)
    end
end
answer("created.txt", function()
    press("a")
end)
confirm()
wait_for(function()
    return vim.fn.filereadable(root .. "/created.txt") == 1
end, "a must create file")
answer("created-dir", function()
    press("A")
end)
confirm()
wait_for(function()
    return vim.fn.isdirectory(root .. "/created-dir") == 1
end, "A must create directory")
entry("created.txt")
answer("renamed.txt", function()
    press("r")
end)
confirm()
wait_for(function()
    return vim.fn.filereadable(root .. "/renamed.txt") == 1 and vim.fn.filereadable(root .. "/created.txt") == 0
end, "r must rename file")
entry("created-dir")
answer("renamed-dir", function()
    press("r")
end)
confirm()
wait_for(function()
    return vim.fn.isdirectory(root .. "/renamed-dir") == 1 and vim.fn.isdirectory(root .. "/created-dir") == 0
end, "r must rename directory")
entry("renamed.txt")
answer("destination", function()
    press("m")
end)
confirm()
wait_for(function()
    return vim.fn.filereadable(root .. "/destination/renamed.txt") == 1
        and vim.fn.filereadable(root .. "/renamed.txt") == 0
end, "m must move instead of copy")
entry("renamed.txt")
press("d")
confirm()
wait_for(function()
    return vim.fn.filereadable(root .. "/destination/renamed.txt") == 0
end, "d must trash temporary file")
local destination_buf = vim.api.nvim_get_current_buf()
open_dir(root)
entry("renamed-dir")
-- A cached Oil buffer stays oil_ready while refreshing, but is temporarily nomodifiable.
-- Hold its real directory listing so the move must wait for that refresh to finish.
local files = require("oil.adapters.files")
local original_list = files.list
local resume_listing
files.list = function(url, columns, callback)
    if url == vim.api.nvim_buf_get_name(destination_buf) then
        files.list = original_list
        resume_listing = function()
            original_list(url, columns, callback)
        end
    else
        return original_list(url, columns, callback)
    end
end
vim.b[destination_buf].oil_dirty = {}
answer("destination", function()
    press("m")
end)
wait_for(function()
    return resume_listing ~= nil
end, "move destination must start its pending refresh")
assert(vim.b[destination_buf].oil_ready and vim.b[destination_buf].oil_rendering)
assert(not vim.bo[destination_buf].modifiable)
assert(vim.fn.isdirectory(root .. "/renamed-dir") == 1, "refresh must not stage source deletion")
assert(vim.fn.isdirectory(root .. "/destination/renamed-dir") == 0)
resume_listing()
confirm()
wait_for(function()
    return vim.fn.isdirectory(root .. "/destination/renamed-dir") == 1
        and vim.fn.isdirectory(root .. "/renamed-dir") == 0
end, "m must move a directory without changing its type")
press("?")
assert(vim.bo.filetype ~= "oil", "? must open Oil help")
vim.api.nvim_win_close(0, true)

-- Prompt cancellation and a directory that cannot be edited must never stage source deletion.
open_dir(root)
entry("original.txt")
local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
answer(nil, function()
    press("r")
end)
assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
answer("../outside", function()
    press("r")
end)
assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
local read_only = root .. "/read-only"
vim.fn.mkdir(read_only)
vim.uv.fs_chmod(read_only, 365)
answer(read_only, function()
    press("m")
end)
wait_for(function()
    return oil.get_current_dir() == read_only .. "/" and vim.b.oil_ready and not vim.b.oil_rendering
end, "read-only move destination must be inspected")
assert(not vim.bo.modifiable, "read-only destination must remain uneditable after loading")
assert(vim.fn.filereadable(root .. "/original.txt") == 1)
assert(vim.fn.filereadable(read_only .. "/original.txt") == 0)
assert(not vim.bo.modified, "read-only move must not modify destination")
vim.uv.fs_chmod(read_only, 493)

vim.cmd.cd(original_cwd)
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "oil" then
        vim.api.nvim_buf_delete(buf, { force = true })
    end
end
assert(root:match("keybinding%-runtime$"), "cleanup must target the test directory")
vim.fn.delete(root, "rf")
print("Neovim shared mappings and real Oil sidebar/mutation checks passed")
