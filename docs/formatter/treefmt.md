# treefmt 設定

[treefmt](https://github.com/numtide/treefmt) を使用して、複数のフォーマッターを統一的に管理します。

## 概要

treefmt は「ワンコマンドで全てをフォーマット」するためのツールです。各言語のフォーマッターを並列実行し、変更されたファイルのみを処理します。

## インストール

```bash
# nix
nix-env -iA nixpkgs.treefmt

# nix (flakes)
nix profile install nixpkgs#treefmt

# cargo
cargo install treefmt
```

## 設定ファイル

[treefmt.toml](../../treefmt.toml)

```toml
[formatter.nix]
command = "nixfmt"
includes = ["*.nix"]

[formatter.oxfmt]
command = "oxfmt"
options = ["--write"]
includes = ["*.json", "*.yaml", "*.yml"]

[formatter.shfmt]
command = "shfmt"
options = ["-w"]
includes = ["*.sh"]

[formatter.powershell]
command = "pwsh"
options = [
  "-NoProfile",
  "-Command",
  "& { ... }"
]
includes = ["*.ps1"]

[formatter.taplo]
command = "taplo"
options = ["format"]
includes = ["*.toml"]

[formatter.stylua]
command = "stylua"
includes = ["*.lua"]

[formatter.dprint]
command = "dprint"
options = ["fmt"]
includes = ["*.md"]
```

## 使用方法

```bash
# 全ファイルをフォーマット
treefmt

# 特定のファイルをフォーマット
treefmt path/to/file.md

# チェックのみ（CI 用）
treefmt --check

# 変更ファイルのみ
treefmt --changed

# 詳細出力
treefmt --verbose

# 統計情報を表示
treefmt --stats
```

## 設定オプション

### formatter セクション

| オプション | 説明 | 例 |
|-----------|------|-----|
| `command` | フォーマッターコマンド | `"nixfmt"` |
| `options` | コマンドオプション | `["--write"]` |
| `includes` | 対象ファイルパターン | `["*.nix"]` |
| `excludes` | 除外ファイルパターン | `["*.min.js"]` |

### グローバル設定

```toml
# ルートディレクトリ
[global]
excludes = ["node_modules/**", ".git/**"]
```

## エディター統合

### VSCode / Cursor

拡張機能: [treefmt-vscode](https://marketplace.visualstudio.com/items?itemName=ibecker.treefmt-vscode)

```json
{
  "editor.defaultFormatter": "ibecker.treefmt-vscode",
  "editor.formatOnSave": true
}
```

### Zed

```json
{
  "formatter": {
    "external": {
      "command": "treefmt",
      "arguments": ["--stdin", "{buffer_path}"]
    }
  }
}
```

> **Note**: treefmt は stdin モードのサポートが限定的なため、言語別のフォーマッター設定が推奨されます。

## pre-commit 統合

[.pre-commit-config.yaml](../../.pre-commit-config.yaml)

```yaml
repos:
  - repo: local
    hooks:
      - id: treefmt
        name: treefmt
        entry: treefmt --fail-on-change
        language: system
        pass_filenames: false
```

## CI 統合

### GitHub Actions

```yaml
- name: Check formatting
  run: treefmt --check
```

### Nix flake

```nix
{
  outputs = { self, nixpkgs, treefmt-nix }: {
    checks.x86_64-linux.formatting = treefmt-nix.lib.mkWrapper nixpkgs.legacyPackages.x86_64-linux {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
      programs.shfmt.enable = true;
    };
  };
}
```

## トラブルシューティング

### キャッシュのクリア

```bash
rm -rf .treefmt-cache
```

### 特定のフォーマッターをスキップ

```bash
treefmt --exclude-formatter powershell
```

### デバッグ

```bash
treefmt --verbose --no-cache
```

## 参考リンク

- [treefmt GitHub](https://github.com/numtide/treefmt)
- [treefmt-nix](https://github.com/numtide/treefmt-nix) - Nix flake 統合
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=ibecker.treefmt-vscode)
