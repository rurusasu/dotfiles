# Formatter AGENTS

フォーマッター設定に関するワークフローノート。

## 概要

このプロジェクトでは [treefmt](https://github.com/numtide/treefmt) を使用して複数のフォーマッターを統一的に管理しています。

## 設定アーキテクチャ

```
.treefmt.toml (source of truth)
      │
      ├── formatter settings
      │   ├── command
      │   ├── options
      │   └── includes
      │
      └── nix/flakes/treefmt.nix
          └── installs formatters via Nix
              └── programs.*.enable = true
```

## 設定ファイル一覧

| ファイル | 用途 | ドキュメント |
|----------|------|--------------|
| `.treefmt.toml` | treefmt メイン設定 | [treefmt.md](./treefmt.md) |
| `.stylua.toml` | Lua フォーマッター | [lua.md](./lua.md) |
| `.taplo.toml` | TOML フォーマッター | [toml.md](./toml.md) |
| `.dprint.json` | Markdown フォーマッター | [markdown.md](./markdown.md) |
| `.oxfmtrc.json` | JSON/YAML フォーマッター | [json-yaml.md](./json-yaml.md) |

## フォーマッター一覧

| 言語 | ツール | treefmt-nix | 対象 |
|------|--------|-------------|------|
| Nix | nixfmt | `programs.nixfmt.enable` | `*.nix` |
| Shell | shfmt | `programs.shfmt.enable` | `*.sh` |
| TOML | taplo | `programs.taplo.enable` | `*.toml` |
| Lua | stylua | `programs.stylua.enable` | `*.lua` |
| Markdown | dprint | `programs.dprint.enable` | `*.md` |
| JSON/YAML | oxfmt | `programs.oxfmt.enable` | `*.json`, `*.yaml`, `*.yml` |
| PowerShell | PSScriptAnalyzer | カスタム設定 | `*.ps1` |

## 使用方法

```bash
# Nix flake 経由（推奨）
nix fmt

# treefmt 直接実行
treefmt

# チェックのみ（CI用）
treefmt --check
```

## 新しいフォーマッターの追加

1. **treefmt-nix に存在する場合**:
   - `nix/flakes/treefmt.nix` で `programs.<name>.enable = true` を追加
   - `.treefmt.toml` にフォーマッター設定を追加

2. **treefmt-nix に存在しない場合** (PowerShell のように):
   - `nix/flakes/treefmt.nix` の `settings.formatter` にカスタム設定を追加
   - `.treefmt.toml` にフォーマッター設定を追加

## ドキュメント

| ファイル | 内容 |
|----------|------|
| [README.md](./README.md) | 概要・クイックスタート |
| [treefmt.md](./treefmt.md) | treefmt 統合設定 |
| [nix.md](./nix.md) | Nix (nixfmt) |
| [shell.md](./shell.md) | Shell (shfmt) |
| [lua.md](./lua.md) | Lua (StyLua) |
| [markdown.md](./markdown.md) | Markdown (dprint) |
| [toml.md](./toml.md) | TOML (taplo) |
| [json-yaml.md](./json-yaml.md) | JSON/YAML (oxfmt) |
| [powershell.md](./powershell.md) | PowerShell (PSScriptAnalyzer) |

## 参照リンク

- [treefmt 公式](https://treefmt.com/)
- [treefmt-nix](https://github.com/numtide/treefmt-nix)
- [treefmt-nix examples](https://github.com/numtide/treefmt-nix/tree/main/examples)
