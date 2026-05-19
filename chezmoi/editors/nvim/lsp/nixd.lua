return {
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
