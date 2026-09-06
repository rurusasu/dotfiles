-- Test the non-Nix installer without downloading/building any language.
local root = vim.fn.getcwd() .. "/chezmoi/dot_config/nvim"
vim.opt.rtp:prepend(root)
local languages = vim.json.decode(table.concat(vim.fn.readfile(root .. "/treesitter.json"), "\n"))
local installed_queries = vim.deepcopy(languages)
table.remove(installed_queries, 1)
local notifications, calls, highlights = {}, {}, 0
vim.notify = function(message)
    notifications[#notifications + 1] = message
end
local executable = vim.fn.executable
vim.fn.executable = function(name)
    return name == "tree-sitter" and 1 or executable(name)
end
package.loaded["config.treesitter"] = {
    start = function()
        highlights = highlights + 1
    end,
}
local success = false
local broken_query
vim.fn.filereadable = function(path)
    return broken_query and path:find("/" .. broken_query .. "/highlights.scm", 1, true) and 0 or 1
end
package.loaded["nvim-treesitter"] = {
    setup = function() end,
    get_installed = function(kind)
        return kind == "parsers" and languages or installed_queries
    end,
    install = function(missing, opts)
        calls[#calls + 1] = { languages = missing, opts = opts }
        return {
            await = function(_, callback)
                callback(nil, success)
            end,
        }
    end,
}
local spec = dofile(root .. "/lua/plugins/treesitter.lua")[1]
spec.config()
vim.wait(1000, function()
    return #notifications > 0
end)
assert(#calls == 1 and vim.deep_equal(calls[1].languages, { languages[1] }))
assert(calls[1].opts.force, "partial parser/query installs must be repaired")
assert(notifications[1]:find("Parser installation failed"), "false result must not be treated as success")
assert(highlights == 0, "failed installation must not resume highlighting")
success = true
spec.config()
assert(
    vim.wait(1000, function()
        return highlights > 0
    end),
    "successful install resumes highlighting"
)
installed_queries = languages
spec.config()
assert(#calls == 2, "complete installations must not rebuild on startup")
broken_query = languages[2]
spec.config()
assert(#calls == 3 and vim.deep_equal(calls[3].languages, { broken_query }), "empty query directories must be repaired")
print("Parser installer repair/failure/success checks passed")
