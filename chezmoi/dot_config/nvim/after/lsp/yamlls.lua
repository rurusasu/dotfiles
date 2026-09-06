---@type vim.lsp.Config
return {
    settings = {
        yaml = {
            format = { enable = true },
            validate = true,
            completion = true,
            hover = true,
            schemaStore = { enable = true },
        },
    },
}
