return {
    settings = {
        gopls = {
            usePlaceholders = true,
            semanticTokens = true,
            staticcheck = true,
            gofumpt = true,
            hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
            },
            analyses = {
                unusedparams = true,
                shadow = true,
                nilness = true,
                unusedwrite = true,
                useany = true,
            },
        },
    },
}
