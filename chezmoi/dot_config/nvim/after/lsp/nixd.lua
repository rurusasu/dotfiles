---@type vim.lsp.Config
return {
    cmd = vim.fn.has("win32") == 1 and { "node", vim.fn.expand("~/.local/bin/nix-lsp-wsl-proxy.mjs") } or { "nixd" },
    settings = {
        nixd = {
            formatting = { command = { "nixfmt" } },
            options = {
                nixos = {
                    expr = '(builtins.getFlake (builtins.getEnv "HOME" + "/.dotfiles")).nixosConfigurations.nixos.options',
                },
            },
        },
    },
}
