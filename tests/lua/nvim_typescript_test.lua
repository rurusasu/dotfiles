-- DOTFILES_NVIM_LSPCONFIG=/existing/nvim-lspconfig nvim --headless -u NONE -i NONE -l tests/lua/nvim_typescript_test.lua
-- Run the real upstream root callbacks against a virtual filesystem/process
-- boundary. No npm installs or language-server processes are needed.
local root = vim.fn.getcwd() .. "/chezmoi/dot_config/nvim"
local upstream = assert(vim.env.DOTFILES_NVIM_LSPCONFIG, "set DOTFILES_NVIM_LSPCONFIG")
vim.opt.rtp:prepend(upstream)
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/after")

local native_defaults = vim.lsp.config.tsc
local native_settings = native_defaults and native_defaults.settings
assert(type(vim.lsp.config.ts_ls.root_dir) == "function", "upstream root detection required")
local old_root, old_executable, old_system, old_start = vim.fs.root, vim.fn.executable, vim.system, vim.lsp.rpc.start
local bins, projects, calls = {}, {}, {}
local spawn
vim.fn.executable = function(bin)
    return bins[bin] and 1 or 0
end
vim.system = function(command)
    assert(command[2] == "--version")
    local result = assert(bins[command[1]], "must check executable before probing")
    calls[#calls + 1] = command[1]
    if result.throw then
        error("executable disappeared before spawn")
    end
    return {
        wait = function(_, timeout)
            assert(timeout == 3000, "version probes must be bounded")
            return { code = result.code or 0, stdout = result.stdout }
        end,
    }
end
vim.fs.root = function(buf, markers)
    local project = assert(projects[buf], "unexpected root lookup")
    if markers[1] == "deno.json" then
        return project.deno
    elseif markers[1] == "deno.lock" then
        return project.deno_lock
    elseif markers[1] == ".git" then
        return project.root
    end
    -- Ensure the actual upstream lockfile priority list remains in use.
    assert(type(markers[1]) == "table" and vim.list_contains(markers[1], "pnpm-lock.yaml"))
    assert(markers[2][1] == ".git")
    return project.root
end
vim.lsp.rpc.start = function(command)
    spawn = command
    return {} -- root selection and command construction only; no server IO
end

local native = { stdout = "Version 7.0.2" }
local legacy = { stdout = "Version 5.9.3" }
local function local_bin(project, name)
    return vim.fs.joinpath(project, "node_modules", ".bin", name)
end
local function buffer(project)
    local buf = vim.api.nvim_create_buf(false, true)
    projects[buf] = type(project) == "table" and project or { root = project }
    return buf
end

local lsp = require("config.lsp")
lsp.setup() -- no executables and no current project
assert(vim.lsp.is_enabled("tsc") and vim.lsp.is_enabled("ts_ls"), "defer availability to each root")
assert(vim.lsp.is_enabled("oxlint"), "project-local oxlint must not be excluded at startup")
assert(vim.list_contains(vim.lsp.config.oxlint.filetypes, "astro"), "preserve upstream Astro support")
assert(not vim.lsp.is_enabled("lua_ls"), "missing static commands stay disabled")
local native_root = vim.lsp.config.tsc.root_dir
lsp.setup()
assert(vim.lsp.config.tsc.root_dir == native_root, "setup must not wrap root callbacks twice")
assert(#vim.api.nvim_get_autocmds({ group = "DotfilesLsp", event = "FileType" }) == 1)
assert(
    vim.deep_equal(vim.lsp.config.tsc.filetypes, vim.lsp.config.ts_ls.filetypes),
    "native TypeScript must not attach to unrelated languages, even with older upstream defaults"
)
if native_settings then
    assert(vim.deep_equal(vim.lsp.config.tsc.settings, native_settings), "upstream native settings must survive")
end
assert(vim.lsp.config.ts_ls.init_options.hostInfo == "neovim")
assert(vim.lsp.config.ts_ls.commands["editor.action.showReferences"], "upstream commands must survive")

local checks = 0
local function check(buf, expected, expected_bin, reverse)
    local activated = {}
    for _, name in ipairs(reverse and { "ts_ls", "tsc" } or { "tsc", "ts_ls" }) do
        local cfg = vim.lsp.config[name]
        cfg.root_dir(buf, function(dir)
            activated[#activated + 1] = name
            cfg.cmd({}, { root_dir = dir })
            assert(spawn[1] == expected_bin, "wrong executable: " .. tostring(spawn[1]))
            assert(spawn[#spawn] == "--stdio")
            assert((spawn[2] == "--lsp") == (name == "tsc"))
        end)
    end
    assert(#activated == (expected and 1 or 0), "must activate exactly one server or none")
    assert(activated[1] == expected, "wrong server: " .. tostring(activated[1]))
    checks = checks + 1
end

-- A buffer without a server does not disable future project-local activation.
local later = buffer("/virtual/later")
check(later)
bins[local_bin("/virtual/later", "tsc")] = native
check(later, "tsc", local_bin("/virtual/later", "tsc"), true)

-- A successful choice is stable even if executable discovery changes later.
bins = { ["typescript-language-server"] = {} }
check(later, "tsc", local_bin("/virtual/later", "tsc"))

bins = { ["tsc"] = native, ["typescript-language-server"] = {} }
check(buffer("/virtual/global7"), "tsc", "tsc")
bins = { ["tsgo"] = native, ["typescript-language-server"] = {} }
check(buffer("/virtual/tsgo"), "tsc", "tsgo", true)
bins = { [local_bin("/virtual/local-tsgo", "tsgo")] = native }
check(buffer("/virtual/local-tsgo"), "tsc", local_bin("/virtual/local-tsgo", "tsgo"))
bins = { [local_bin("/virtual/old-local", "tsc")] = legacy, ["tsc"] = native }
check(buffer("/virtual/old-local"), "tsc", "tsc")
bins = { [local_bin("/virtual/prefer-local", "tsc")] = native, ["tsc"] = native }
check(buffer("/virtual/prefer-local"), "tsc", local_bin("/virtual/prefer-local", "tsc"))

for _, version in ipairs({ "5.9.3", "6.0.0" }) do
    bins = { ["tsc"] = { stdout = "Version " .. version }, ["typescript-language-server"] = {} }
    check(buffer("/virtual/legacy-" .. version), "ts_ls", "typescript-language-server", true)
end
bins = {
    [local_bin("/virtual/local-legacy", "tsc")] = legacy,
    [local_bin("/virtual/local-legacy", "typescript-language-server")] = {},
}
check(buffer("/virtual/local-legacy"), "ts_ls", local_bin("/virtual/local-legacy", "typescript-language-server"))
bins = { ["tsc"] = legacy }
check(buffer("/virtual/no-language-server"))
bins = {}
local absent = buffer("/virtual/install-later")
check(absent)
bins = { [local_bin("/virtual/install-later", "typescript-language-server")] = {} }
check(absent, "ts_ls", local_bin("/virtual/install-later", "typescript-language-server"))

-- Failed version probes must continue to the next candidate/fallback.
for index, failure in ipairs({
    { code = 1, stdout = "Version 7.0.2" },
    { code = 124, stdout = "" },
    { stdout = "unrecognized version output" },
    { throw = true },
}) do
    bins = { ["tsc"] = failure, ["typescript-language-server"] = {} }
    check(buffer("/virtual/failure-" .. index), "ts_ls", "typescript-language-server")
end
bins = { ["tsc"] = { throw = true }, ["tsgo"] = native }
check(buffer("/virtual/broken-tsc"), "tsc", "tsgo")

-- Deno exclusion is delegated to upstream before any executable probe.
vim.g.dotfiles_typescript_server = "ts_ls"
bins = { ["tsc"] = native, ["typescript-language-server"] = {} }
check(buffer("/virtual/explicit-legacy"), "ts_ls", "typescript-language-server")
vim.g.dotfiles_typescript_server = "tsc"
bins = { ["tsc"] = legacy, ["typescript-language-server"] = {} }
check(buffer("/virtual/explicit-native-unavailable"))
vim.g.dotfiles_typescript_server = nil

bins = { ["tsc"] = native, ["typescript-language-server"] = {} }
for _, project in ipairs({
    { root = "/virtual/deno", deno = "/virtual/deno" },
    { root = "/virtual/mono", deno = "/virtual/mono/packages/deno" },
    { root = "/virtual/mono", deno_lock = "/virtual/mono/packages/deno" },
    { deno = "/virtual/standalone-deno" },
}) do
    local before = #calls
    check(buffer(project))
    assert(#calls == before, "Deno files must not probe TypeScript binaries")
end
-- A nested Node project still wins over an outer Deno configuration.
check(buffer({ root = "/virtual/deno/node", deno = "/virtual/deno" }), "tsc", "tsc")
check(buffer({ root = "/virtual/equal-lock", deno_lock = "/virtual/equal-lock" }), "tsc", "tsc")
check(buffer({}), "tsc", "tsc") -- upstream loose-file cwd fallback

-- A FileType event is already in flight, so vim.lsp.enable() alone cannot
-- replay it for the current buffer. Verify the explicit native start path.
local start = vim.lsp.start
local started = {}
vim.lsp.start = function(config, opts)
    started[#started + 1] = { config = config, opts = opts }
end
bins = { ["lua-language-server"] = {} }
vim.bo.filetype = "lua"
vim.api.nvim_exec_autocmds("FileType", { buffer = vim.api.nvim_get_current_buf() })
assert(vim.lsp.is_enabled("lua_ls"), "later PATH availability must be reconsidered")
assert(
    vim.wait(1000, function()
        return #started > 0
    end),
    "newly available server must start for the current buffer"
)
assert(started[1].config.name == "lua_ls", "current buffer must start the newly available server")
assert(started[1].opts.bufnr == vim.api.nvim_get_current_buf(), "server must attach to the current buffer")
vim.lsp.start = start
vim.bo.filetype = ""

-- Function cmd is not proof of availability. Gate absent YAML servers per
-- root, then permit a binary that appears in a later project.
local yamlbuf = buffer("/virtual/yaml")
local attached = false
bins = {}
vim.lsp.config.yamlls.root_dir(yamlbuf, function()
    attached = true
end)
assert(not attached, "missing function-command executables must not attach")
bins[local_bin("/virtual/yaml", "yaml-language-server")] = {}
vim.lsp.config.yamlls.root_dir(yamlbuf, function(dir)
    attached = dir == "/virtual/yaml"
end)
assert(attached, "later project-local YAML server must attach")

-- The unchanged upstream function resolves oxlint in a later project's root,
-- even though no global executable was available when setup first ran.
local later_oxlint = local_bin("/virtual/later-oxlint", "oxlint")
bins = { [later_oxlint] = {} }
vim.lsp.config.oxlint.cmd({}, { root_dir = "/virtual/later-oxlint" })
assert(spawn[1] == later_oxlint and spawn[2] == "--lsp", "resolve later project-local oxlint")

for name in pairs(lsp.servers) do
    vim.lsp.enable(name, false)
end
vim.fs.root, vim.fn.executable, vim.system, vim.lsp.rpc.start = old_root, old_executable, old_system, old_start
print(("TypeScript routing: %d cases passed (upstream roots, mocked executables/RPC)"):format(checks))
