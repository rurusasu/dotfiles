-- Exercise the configured picker callbacks with real Snacks and Poppler.
vim.g.mapleader = " "
local snacks = require("snacks")
local preview = require("snacks.picker.preview")
vim.api.nvim_exec_autocmds("VimEnter", {})

-- Space is also the leader; using it as a terminal-mode mapping prefix delays shell input.
for _, map in ipairs(vim.api.nvim_get_keymap("t")) do
    assert(map.lhs:sub(1, 1) ~= " ", "terminal-mode mappings must not use Space as a prefix: " .. map.lhs)
end

local config = require("snacks.picker.config")
local function resolve(opts)
    return config.preview(config.get(opts))
end
local file_preview = resolve({ source = "files" })
assert(resolve({ source = "git_log" }) == preview.git_show, "Git must retain its dedicated preview")
assert(resolve({ source = "registers" }) == preview.preview, "registers must retain their text preview")
local custom = function() end
assert(resolve({ source = "files", preview = custom }) == custom, "per-picker preview overrides must survive")

-- The smart picker and custom multi-source pickers must keep source-specific previews.
local mixed = resolve({ multi = { "files", "git_log", { finder = "files" } } })
local original_git_show = preview.git_show
local git_calls = 0
preview.git_show = function()
    git_calls = git_calls + 1
end
resolve({ multi = { "files", "git_log" } })({ item = { source_id = 2 } })
preview.git_show = original_git_show
assert(git_calls == 1, "mixed pickers must use the Git preview for Git items")

local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local pdf_path = directory .. "/blank.pdf"
local objects = {
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] /Contents 4 0 R >>",
    "<< /Length 0 >>\nstream\n\nendstream",
}
local pdf, offsets = "%PDF-1.4\n", {}
for i, object in ipairs(objects) do
    offsets[i] = #pdf
    pdf = pdf .. i .. " 0 obj\n" .. object .. "\nendobj\n"
end
local xref = #pdf
pdf = pdf .. "xref\n0 5\n0000000000 65535 f \n"
for _, offset in ipairs(offsets) do
    pdf = pdf .. string.format("%010d 00000 n \n", offset)
end
pdf = pdf .. "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n" .. xref .. "\n%%EOF\n"
vim.fn.writefile(vim.split(pdf, "\n", { plain = true }), pdf_path, "b")

-- Replace only the terminal image output; conversion and path resolution stay real.
local original_image = preview.image
local outputs = {}
preview.image = function(ctx)
    local path = snacks.picker.util.path(ctx.item)
    local handle = assert(io.open(path, "rb"))
    local signature = handle:read(8)
    handle:close()
    assert(signature == "\137PNG\r\n\26\n", "the image preview must receive a generated PNG")
    outputs[#outputs + 1] = path
    return path
end
local item = { file = "blank.pdf", cwd = directory, _path = pdf_path }
local output = file_preview({ item = item })
assert(output and output ~= pdf_path, "the PDF must be converted before image display")
assert(item.file == "blank.pdf" and item._path == pdf_path, "conversion must preserve the original picker item")
local smart = resolve({ source = "smart" })
smart({ item = vim.tbl_extend("force", item, { source_id = 1 }) })
assert(#outputs == 2, "smart pickers must convert the PDF before image display")
mixed({ item = vim.tbl_extend("force", item, { source_id = 3 }) })
assert(#outputs == 3, "custom multi-source pickers must convert the PDF before image display")

-- A normal file must still reach the built-in file preview and populate its buffer.
local text_path = directory .. "/note.txt"
vim.fn.writefile({ "ordinary text" }, text_path)
local buf = vim.api.nvim_create_buf(false, true)
file_preview({
    item = { file = text_path },
    buf = buf,
    picker = { opts = config.get({ source = "files" }) },
    preview = {
        reset = function() end,
        set_title = function() end,
        highlight = function() end,
        loc = function() end,
        set_lines = function(_, lines)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        end,
    },
})
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "ordinary text" }))

local original_notify = vim.notify
local warnings = {}
vim.notify = function(message, level)
    assert(level == vim.log.levels.WARN, "preview failures must be warnings")
    warnings[#warnings + 1] = message
end
local original_path = vim.env.PATH
vim.env.PATH = directory
assert(file_preview({ item = item }) == false, "missing Poppler must fail gracefully")
vim.env.PATH = original_path
local invalid_path = directory .. "/invalid.pdf"
vim.fn.writefile({ "not a PDF" }, invalid_path)
assert(file_preview({ item = { file = invalid_path } }) == false, "failed conversion must not display an image")
assert(#warnings == 2 and warnings[1]:find("pdftoppm") and warnings[2]:find("PDF conversion failed"))

vim.notify = original_notify
preview.image = original_image
vim.api.nvim_buf_delete(buf, { force = true })
for _, path in ipairs(outputs) do
    vim.fn.delete(path)
end

-- Terminal windows must keep vertical-only scrolling.
local long_path = directory .. "/terminal.txt"
vim.fn.writefile({ string.rep("x", 200) }, long_path)
local terminal = snacks.terminal.open({ "cat", long_path }, {
    interactive = false,
    win = { position = "bottom" },
})
assert(terminal and terminal.win, "the snacks terminal must open a window")
-- Esc must reach the shell; <C-q> is the only terminal-mode escape.
for _, map in ipairs(vim.api.nvim_buf_get_keymap(terminal.buf, "t")) do
    assert(map.lhs ~= "<Esc>", "the snacks terminal must not capture Esc: " .. map.lhs)
end
assert(vim.wo[terminal.win].wrap, "the snacks terminal must wrap instead of scrolling horizontally")
assert(vim.wo[terminal.win].sidescrolloff == 0, "the snacks terminal must not reserve a horizontal scroll margin")
local leftcol = vim.api.nvim_win_call(terminal.win, function()
    vim.cmd("normal! zl")
    return vim.fn.winsaveview().leftcol
end)
assert(leftcol == 0, "the snacks terminal must not allow horizontal view movement")
terminal:close()

-- The floating-terminal mapping must use Snacks' hide/reuse lifecycle.
local toggle_float = vim.fn.maparg("<leader>tf", "n", false, true).callback
toggle_float()
local floating = assert(snacks.terminal.get({ vim.o.shell }, { create = false }))
local floating_buf = floating.buf
local floating_job = vim.b[floating_buf].terminal_job_id
assert(vim.api.nvim_win_get_config(floating.win).relative ~= "", "the terminal must be floating")
toggle_float()
assert(not floating:win_valid() and floating:buf_valid(), "hiding the terminal must preserve its buffer")
toggle_float()
assert(floating.buf == floating_buf and floating:win_valid(), "toggling must reuse the floating terminal")
assert(vim.fn.jobwait({ floating_job }, 0)[1] == -1, "the reused shell must remain running")
vim.api.nvim_clear_autocmds({ event = "TermClose", group = floating.augroup, buffer = floating.buf })
floating:close()
vim.cmd.stopinsert()

vim.fn.delete(directory, "rf")
print("Snacks preview callbacks: PDF conversion, text, multi-source dispatch and errors passed")
