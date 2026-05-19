return {
    settings = {
        ["rust-analyzer"] = {
            checkOnSave = true,
            check = { command = "clippy" },
            inlayHints = {
                bindingModeHints = { enable = true },
                closureCaptureHints = { enable = true },
                closureReturnTypeHints = { enable = "always" },
                lifetimeElisionHints = { enable = "skip_trivial" },
                typeHints = { hideNamedConstructor = false },
            },
            procMacro = { enable = true },
            cargo = { allFeatures = true, buildScripts = { enable = true } },
        },
    },
}
