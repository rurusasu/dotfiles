-- Run with the Home Manager package and plugin data from nix/modules/nvim.
local root = vim.fn.getcwd() .. "/nix/modules/nvim"
vim.opt.rtp:prepend(root)
vim.cmd.packloadall()
local ts = require("config.treesitter")
ts.setup()
local languages = {}
for _, path in ipairs(vim.api.nvim_get_runtime_file("parser/*", true)) do
    local lang = vim.fn.fnamemodify(path, ":t:r")
    if not vim.list_contains(languages, lang) then
        languages[#languages + 1] = lang
    end
end
assert(#languages > 0, "the Home Manager runtime must supply parsers")
for _, lang in ipairs(languages) do
    assert(vim.treesitter.language.add(lang), "missing parser: " .. lang)
    local query = assert(vim.treesitter.query.get(lang, "highlights"), "missing highlights: " .. lang)
    assert(#query.captures > 0, "empty highlights query: " .. lang)
    vim.treesitter.query.get(lang, "injections") -- also compile optional injection queries
end
for _, sample in ipairs({
    { "sh", "bash", "echo hello" },
    { "javascriptreact", "javascript", "const x = <div>hello</div>;" },
    { "typescriptreact", "tsx", "const x: number = 1;" },
    { "python", "python", "answer = 42" },
    { "nix", "nix", "{ answer = 42; }" },
}) do
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { sample[3] })
    vim.bo[buf].filetype = sample[1]
    local parser = assert(vim.treesitter.get_parser(buf))
    assert(parser:lang() == sample[2])
    assert(vim.treesitter.highlighter.active[buf], "highlighter not active: " .. sample[1])
    local tree = parser:parse()[1]
    local query = assert(vim.treesitter.query.get(sample[2], "highlights"))
    local captures = 0
    for _ in query:iter_captures(tree:root(), buf, 0, -1) do
        captures = captures + 1
    end
    assert(captures > 0, "no actual highlights: " .. sample[1])
end
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "```python", "answer = 42", "```" })
vim.bo[buf].filetype = "markdown"
local parser = assert(vim.treesitter.get_parser(buf, "markdown"))
parser:parse(true)
assert(parser:children().python, "Markdown Python injection must load")
print(("%d parsers/queries and native highlighting/injections passed"):format(#languages))
