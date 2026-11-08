-- Run with the generated Home Manager init and native plugin pack, in isolated XDG dirs.
local original_cwd = vim.uv.cwd()
local root = vim.fn.tempname() .. "-keybinding-runtime"
vim.fn.mkdir(root .. "/child", "p")
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
local terminal
wait_for(function()
    terminal = Snacks.terminal.get({ "lazygit" }, { cwd = root, create = false })
    return terminal and vim.api.nvim_buf_is_valid(terminal.buf)
end, "Space g g must launch Lazygit")
local job = vim.b[terminal.buf].terminal_job_id
assert(job and vim.fn.jobwait({ job }, 0)[1] == -1, "Lazygit process must be running")
-- Terminate only this probe's child; suppress its expected forced-exit notification.
vim.api.nvim_clear_autocmds({ event = "TermClose", group = terminal.augroup, buffer = terminal.buf })
vim.fn.jobstop(job)
terminal:close()
vim.cmd.stopinsert()

vim.cmd.edit(root .. "/original.txt")
press("-")
wait_for(function()
    return vim.bo.filetype == "oil" and vim.bo.modifiable
end, "- must open Oil")
press("<C-c>")

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

vim.cmd.cd(original_cwd)
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "oil" then
        vim.api.nvim_buf_delete(buf, { force = true })
    end
end
assert(root:match("keybinding%-runtime$"), "cleanup must target the test directory")
vim.fn.delete(root, "rf")
print("Neovim shared mappings checks passed")
