# フォーマッター設定

このプロジェクトでは [treefmt-nix](https://github.com/numtide/treefmt-nix) を使用して、複数のフォーマッターを管理しています。
設定値と実行依存の正本は [nix/formatter.nix](../../nix/formatter.nix) です。
設定ファイルは Nix store に生成し、project root には配置しません。

## 対象

| 言語/形式  | フォーマッター   | Nix の設定先                                       |
| ---------- | ---------------- | -------------------------------------------------- |
| Nix        | nixfmt           | `treefmt.programs.nixfmt`                          |
| JSON/YAML  | oxfmt            | `oxfmtConfig` / `treefmt.settings.formatter.oxfmt` |
| Shell      | shfmt            | `treefmt.programs.shfmt`                           |
| PowerShell | PSScriptAnalyzer | `treefmt.settings.formatter.powershell`            |
| TOML       | Taplo            | `treefmt.programs.taplo.settings`                  |
| Lua        | StyLua           | `treefmt.programs.stylua.settings`                 |
| Markdown   | dprint           | `treefmt.programs.dprint.settings`                 |

PowerShell の静的解析設定は [PSScriptAnalyzerSettings.psd1](../../scripts/powershell/PSScriptAnalyzerSettings.psd1) が担当します。

## 使用方法

```bash
nix fmt
nix fmt -- path/to/file.nix
nix fmt -- --fail-on-change
```

`nix develop` 内では `treefmt` も同じ設定で使用できます。
Windows では `task fmt` / `task fmt:check` が WSL の Nix を呼び出します。
[pre-commit](../../.pre-commit-config.yaml) と CI も `nix fmt` を利用します。

## 詳細

- [treefmt](treefmt.md): 設定生成・実行・エディター連携
- [Nix](nix.md)
- [Shell](shell.md)
- [Markdown](markdown.md)
- [TOML](toml.md)
- [PowerShell](powershell.md)
- [JSON/YAML](json-yaml.md)
- [Lua](lua.md)
