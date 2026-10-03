local M = {}

---@class DotfilesTypeScriptServer
---@field name 'tsc'|'ts_ls'
---@field cmd string

---@type table<string, DotfilesTypeScriptServer>
local selected = {}
local configured = false

local function candidates(root, executable)
    return { vim.fs.joinpath(root, "node_modules", ".bin", executable), executable }
end

local function supports_lsp(bin)
    if vim.fn.executable(bin) ~= 1 then
        return false
    end
    -- Match upstream tsc's version check, but bound broken executables and
    -- handle spawn failures so a usable next candidate can still be selected.
    local ok, result = pcall(function()
        return vim.system({ bin, "--version" }, { text = true }):wait(3000)
    end)
    if not ok or result.code ~= 0 then
        return false
    end
    local version = vim.version.parse(result.stdout or "")
    return version ~= nil and version.major >= 7
end

---@param root string
---@return DotfilesTypeScriptServer?
local function select_server(root)
    if selected[root] then
        return selected[root]
    end
    local preferred = vim.g.dotfiles_typescript_server
    assert(
        preferred == nil or preferred == "tsc" or preferred == "ts_ls",
        "dotfiles_typescript_server must be tsc or ts_ls"
    )
    -- Same ordering as nvim-lspconfig's tsc: local tsc, PATH tsc,
    -- local tsgo, PATH tsgo. Older local compilers do not hide native ones.
    for _, executable in ipairs(preferred == "ts_ls" and {} or { "tsc", "tsgo" }) do
        for _, bin in ipairs(candidates(root, executable)) do
            if supports_lsp(bin) then
                selected[root] = { name = "tsc", cmd = bin }
                return selected[root]
            end
        end
    end
    for _, bin in ipairs(preferred == "tsc" and {} or candidates(root, "typescript-language-server")) do
        if vim.fn.executable(bin) == 1 then
            selected[root] = { name = "ts_ls", cmd = bin }
            return selected[root]
        end
    end
    -- Do not cache absence: a later buffer may be opened after npm install.
end

function M.setup()
    if configured then
        return
    end
    local fallback = vim.lsp.config.ts_ls
    if not fallback or type(fallback.root_dir) ~= "function" then
        return -- Server defaults are not present in standalone config checks.
    end
    local upstream_root = fallback.root_dir
    -- Older cached nvim-lspconfig versions may not define tsc yet. The native
    -- transport below still works, but must remain limited to JS/TS buffers.
    local native = vim.lsp.config.tsc
    if not native or not native.filetypes then
        vim.lsp.config("tsc", { filetypes = fallback.filetypes })
    end
    for _, name in ipairs({ "tsc", "ts_ls" }) do
        vim.lsp.config(name, {
            root_dir = function(buf, on_dir)
                -- Keep upstream lockfile/monorepo, loose-file and Deno rules.
                upstream_root(buf, function(root)
                    local server = select_server(root)
                    if server and server.name == name then
                        on_dir(root)
                    end
                end)
            end,
            cmd = function(dispatchers, config)
                local server = assert(selected[config.root_dir], "TypeScript root was not selected")
                assert(server.name == name, "TypeScript server selection changed")
                local command = { server.cmd }
                if name == "tsc" then
                    command[#command + 1] = "--lsp"
                end
                command[#command + 1] = "--stdio"
                return vim.lsp.rpc.start(command, dispatchers)
            end,
        })
    end
    -- Pin a successful choice for each root for this session, just as upstream
    -- tsc caches its binary. This also prevents both clients attaching there.
    configured = true
end

return M
