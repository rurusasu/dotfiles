# フォーマッター設定

このプロジェクトでは [treefmt](https://github.com/numtide/treefmt) を使用して、複数のフォーマッターを統一的に管理しています。

## 概要

| 言語/形式 | フォーマッター | 設定ファイル |
|----------|--------------|-------------|
| Nix | [nixfmt](https://github.com/serokell/nixfmt) | - |
| JSON/YAML | [oxfmt](https://oxc.rs/docs/guide/usage/formatter.html) | [.oxfmtrc.json](../../.oxfmtrc.json) |
| Shell | [shfmt](https://github.com/mvdan/shfmt) | - |
| PowerShell | [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) | [PSScriptAnalyzerSettings.psd1](../../scripts/powershell/PSScriptAnalyzerSettings.psd1) |
| TOML | [taplo](https://taplo.tamasfe.dev/) | [.taplo.toml](../../.taplo.toml) |
| Lua | [StyLua](https://github.com/JohnnyMorganz/StyLua) | [stylua.toml](../../stylua.toml) |
| Markdown | [dprint](https://dprint.dev/) | [dprint.json](../../dprint.json) |

## 設定ファイル

メイン設定: [treefmt.toml](../../treefmt.toml)

詳細: [treefmt 設定](./treefmt.md)

## 詳細ドキュメント

- [treefmt](./treefmt.md) - treefmt 統合設定
- [Nix (nixfmt)](./nix.md) - Nix フォーマット設定
- [Shell (shfmt)](./shell.md) - Shell フォーマット設定
- [Markdown (dprint)](./markdown.md) - Markdown フォーマット設定
- [TOML (taplo)](./toml.md) - TOML フォーマット設定
- [PowerShell](./powershell.md) - PowerShell フォーマット設定
- [JSON/YAML (oxfmt)](./json-yaml.md) - JSON/YAML フォーマット設定
- [Lua (StyLua)](./lua.md) - Lua フォーマット設定

## エディター拡張機能

### VSCode / Cursor

| フォーマッター | 拡張機能 ID |
|--------------|------------|
| treefmt | `ibecker.treefmt-vscode` |
| Nix | `jnoortheen.nix-ide` |
| TOML | `tamasfe.even-better-toml` |
| Markdown | `dprint.dprint` |
| Lua | `JohnnyMorganz.stylua` |
| PowerShell | `ms-vscode.powershell` |
| JSON/YAML | `oxc.oxc-vscode` |
| Shell | `foxundermoon.shell-format` |

### Zed

Zed では `languages` 設定で外部フォーマッターを指定します。
詳細は各フォーマッターのドキュメントを参照してください。

## 使用方法

```bash
# 全ファイルをフォーマット
treefmt

# 特定のファイルをフォーマット
treefmt path/to/file.md

# チェックのみ（変更なし）
treefmt --check
```

## pre-commit 統合

[.pre-commit-config.yaml](../../.pre-commit-config.yaml) で treefmt が自動実行されます。

```bash
# 手動実行
pre-commit run treefmt --all-files
```
