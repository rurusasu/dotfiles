# AGENTS

Purpose: Treesitter syntax highlighting and parsing configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable treesitter |
| `package` | package | pkgs.vimPlugins.nvim-treesitter | Treesitter package |
| `autoLoad` | bool | true | Auto load on startup |
| `nixGrammars` | bool | true | Use Nix-managed grammars |
| `grammarPackages` | list | all grammars | Grammar packages to install |
| `settings.highlight.enable` | bool | false | Enable syntax highlighting |
| `settings.indent.enable` | bool | false | Enable indentation |
| `folding.enable` | bool | false | Enable treesitter-based folding |

## Current Configuration

```nix
plugins.treesitter = {
  enable = true;
  nixGrammars = true;
  settings = {
    highlight.enable = true;
    indent.enable = true;
  };
  grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
    lua vim vimdoc nix bash
    python javascript typescript
    json yaml markdown markdown_inline
  ];
};
```

## Notes

- `nixGrammars = true` avoids read-only Nix store errors
- Grammars are installed via Nix, not runtime download
- Use `grammarPackages` instead of `ensure_installed`

## Sources

- [Nixvim Treesitter Docs](https://nix-community.github.io/nixvim/plugins/treesitter/index.html)
- [nvim-treesitter GitHub](https://github.com/nvim-treesitter/nvim-treesitter)
- [Treesitter NixOS Wiki](https://nixos.wiki/wiki/Treesitter)
