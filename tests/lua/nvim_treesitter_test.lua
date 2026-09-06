-- Run with the Neovim package built from nix/packages/neovim.
local root = vim.fn.getcwd() .. "/chezmoi/dot_config/nvim"
vim.opt.rtp:prepend(root)
local ts = require("config.treesitter")
ts.setup()
assert(vim.env.DOTFILES_NVIM_TREESITTER, "run this test with the Nix-wrapped Neovim")
local runtime = vim.env.DOTFILES_NVIM_TREESITTER
assert(vim.fn.isdirectory(runtime .. "/lua") == 0, "data runtime must not expose plugin code")
assert(vim.fn.isdirectory(runtime .. "/plugin") == 0, "data runtime must not expose startup scripts")
local languages = vim.json.decode(table.concat(vim.fn.readfile(root .. "/treesitter.json"), "\n"))
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
assert(not package.loaded["nvim-treesitter"], "native highlighting must not load the installer")
print(("%d parsers/queries and native highlighting/injections passed"):format(#languages))
