---@type vim.lsp.Config
return {
    settings = {
        bashIde = {
            -- Limit background scanning when a loose file lives in the home directory.
            globPattern = "*@(.sh|.inc|.bash|.command)",
            enableSourceErrorDiagnostics = true,
        },
    },
}
