# treefmt 設定

[treefmt](https://github.com/numtide/treefmt) を使用して、複数のフォーマッターを統一的に管理します。

## 概要

treefmt は「ワンコマンドで全てをフォーマット」するためのツールです。各言語のフォーマッターを並列実行し、変更されたファイルのみを処理します。

## インストール

### Nix (推奨)

```bash
# nix profile (flakes)
nix profile install nixpkgs#treefmt

# nix-env
nix-env -iA nixpkgs.treefmt

# nix run (一時的)
nix run nixpkgs#treefmt -- --help
```

### その他

```bash
# cargo
cargo install treefmt
```

## 設定ファイル

[.treefmt.toml](../../.treefmt.toml)

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

## treefmt-nix 統合

### Nix Flake での設定

[nix/flakes/treefmt.nix](../../nix/flakes/treefmt.nix)

```nix
# treefmt-nix configuration
# Formatter settings are in .treefmt.toml (source of truth)
# This file only installs formatters via Nix
_: {
  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";

        # Install formatters (settings come from .treefmt.toml)
        programs = {
          nixfmt.enable = true; # *.nix
          shfmt.enable = true; # *.sh
          taplo.enable = true; # *.toml
          stylua.enable = true; # *.lua
          dprint.enable = true; # *.md
          oxfmt.enable = true; # *.json, *.yaml, *.yml
        };

        # Custom formatters not in treefmt-nix programs
        settings.formatter = {
          # PowerShell (no built-in support)
          powershell = {
            command = "${pkgs.powershell}/bin/pwsh";
            options = [
              "-NoProfile"
              "-Command"
              "& { ... }"
            ];
            includes = [ "*.ps1" ];
          };
        };
      };
    };
}
```

### treefmt-nix で利用可能なプログラム

| プログラム | 対象ファイル            | Nix設定 | TOML例 |
| ---------- | ----------------------- | ------- | ------ |
| nixfmt     | `*.nix`                 | [programs/nixfmt.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/nixfmt.nix)   | [formatter-nixfmt.toml](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-nixfmt.toml) |
| shfmt      | `*.sh`                  | [programs/shfmt.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/shfmt.nix)     | [formatter-shfmt.toml](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-shfmt.toml) |
| taplo      | `*.toml`                | [programs/taplo.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/taplo.nix)     | [formatter-taplo.toml](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-taplo.toml) |
| stylua     | `*.lua`                 | [programs/stylua.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/stylua.nix)   | [formatter-stylua.toml](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-stylua.toml) |
| dprint     | `*.md` など             | [programs/dprint.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/dprint.nix)   | [formatter-dprint.toml](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-dprint.toml) |
| oxfmt      | `*.json`, `*.yaml` など | [programs/oxfmt.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/oxfmt.nix)     | [formatter-oxfmt.toml](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-oxfmt.toml) |

### Nix flake でのフォーマット実行

```bash
# nix fmt コマンドでフォーマット
nix fmt

# チェックのみ
nix fmt -- --check
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

| オプション | 説明                   | 例             |
| ---------- | ---------------------- | -------------- |
| `command`  | フォーマッターコマンド | `"nixfmt"`     |
| `options`  | コマンドオプション     | `["--write"]`  |
| `includes` | 対象ファイルパターン   | `["*.nix"]`    |
| `excludes` | 除外ファイルパターン   | `["*.min.js"]` |

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

- [treefmt 公式ドキュメント](https://treefmt.com/)
- [treefmt 設定リファレンス](https://treefmt.com/v2.1/getting-started/configure/)
- [treefmt GitHub](https://github.com/numtide/treefmt)
- [treefmt-nix](https://github.com/numtide/treefmt-nix) - Nix flake 統合
- [treefmt-nix examples](https://github.com/numtide/treefmt-nix/tree/main/examples)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=ibecker.treefmt-vscode)
