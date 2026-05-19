# Neovim 0.12 LSP モダン化設計

**日付:** 2026-05-19  
**ブランチ:** feat/nvim-012-lsp  
**スコープ:** chezmoi/editors/nvim, nix/packages/sets.nix

## 目的

Neovim を最新版（nixos-unstable 経由）に更新し、LSP 設定を 0.12 推奨スタイルに刷新する。
Mason を完全に廃止し、Nix（NixOS）と既存 Windows パッケージ管理で LSP サーバーを管理する。

## 現状の問題

- Mason が Nix と並行してサーバーをインストールする（NixOS では FHS 非互換で失敗しうる）
- `on_attach` 関数パターンが非推奨（0.11+ では `LspAttach` autocmd が推奨）
- nvim-cmp + cmp-nvim-lsp + LuaSnip の 5 プラグインが内蔵 completion で代替可能
- サーバー設定がすべてインライン（`lsp/<name>.lua` 分割が推奨）

## アーキテクチャ

### Before

```
Mason (server install) → mason-lspconfig → nvim-lspconfig
                                                 ↓
                         on_attach fn → keymaps + cmp-nvim-lsp capabilities
                                                 ↓
                                   nvim-cmp → cmp-buffer, cmp-path, LuaSnip
```

### After

```
Nix (NixOS) / winget+pnpm (Windows) → PATH に server バイナリ
                                              ↓
               nvim-lspconfig (server defaults: cmd, filetypes, root_dir)
                                              ↓
              lsp/<name>.lua (per-server 設定, Neovim が自動ロード)
                                              ↓
              LspAttach autocmd → keymaps + vim.lsp.completion.enable()
                                              ↓
                              vim.lsp.completion (内蔵) + vim.snippet (内蔵)
```

## 変更内容

### 1. nixpkgs 更新

```bash
nix flake update  # nixos-unstable 最新を取得
```

### 2. プラグイン変更（lua/plugins/init.lua）

**削除:**

- `williamboman/mason.nvim`
- `williamboman/mason-lspconfig.nvim`
- `hrsh7th/nvim-cmp`
- `hrsh7th/cmp-nvim-lsp`
- `hrsh7th/cmp-buffer`
- `hrsh7th/cmp-path`
- `L3MON4D3/LuaSnip`
- `saadparwaiz1/cmp_luasnip`

**更新:**

- `neovim/nvim-lspconfig`: server defaults のみ利用。`LspAttach` autocmd で keymaps と `vim.lsp.completion.enable()` を設定。実行ファイルが PATH にあるサーバーのみ有効化（graceful degradation）。

### 3. lsp/ ディレクトリ新設

`chezmoi/editors/nvim/lsp/<name>.lua` を各サーバーごとに作成：

| ファイル            | サーバー                   | プラットフォーム                            |
| ------------------- | -------------------------- | ------------------------------------------- |
| `nixd.lua`          | nixd                       | NixOS のみ（`executable("nixd")` でガード） |
| `gopls.lua`         | gopls                      | 両プラットフォーム                          |
| `rust_analyzer.lua` | rust-analyzer              | 両プラットフォーム                          |
| `ts_ls.lua`         | typescript-language-server | 両プラットフォーム                          |
| `yamlls.lua`        | yaml-language-server       | 両プラットフォーム                          |
| `taplo.lua`         | taplo                      | 両プラットフォーム                          |
| `bashls.lua`        | bash-language-server       | NixOS のみ                                  |
| `lua_ls.lua`        | lua-language-server        | 両プラットフォーム                          |
| `marksman.lua`      | marksman                   | 両プラットフォーム                          |
| `ruff.lua`          | ruff                       | 両プラットフォーム                          |

各ファイルは server-specific settings のみ返す（`cmd`, `filetypes` は nvim-lspconfig が担当）。

### 4. クロスプラットフォーム戦略

**nvim 設定（プラットフォーム非依存）:**

```lua
local server_bins = {
    gopls = "gopls", rust_analyzer = "rust-analyzer",
    ts_ls = "typescript-language-server", yamlls = "yaml-language-server",
    taplo = "taplo", bashls = "bash-language-server",
    lua_ls = "lua-language-server", marksman = "marksman",
    ruff = "ruff", nixd = "nixd",
}
for name, exe in pairs(server_bins) do
    if vim.fn.executable(exe) == 1 then vim.lsp.enable(name) end
end
```

**Windows パッケージ管理拡張（sets.nix）:**

- `pnpmGlobal` に追加: `typescript-language-server`, `yaml-language-server`
- winget ID を調査・追加: `ruff`（`astral-sh.ruff`）, `lua-language-server`, `marksman`
- `gopls`: PowerShell install script で `go install` （Go は既存 Windows パッケージ）

### 5. 内蔵 Completion

```lua
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
        end
        -- keymaps ...
    end,
})
```

スニペット展開は `vim.snippet`（内蔵）が担当。LuaSnip 不要。

## 成功基準

- NixOS で `nvim` 起動後、LSP が全サーバー（nixd 含む）で正常動作
- Windows で PATH にある LSP サーバーのみ自動有効化
- `:Mason` コマンドが存在しない（削除確認）
- `<C-Space>` または自動補完で内蔵 completion が動作
- 起動時間が現在以下（Mason 初期化がなくなるため改善見込み）
