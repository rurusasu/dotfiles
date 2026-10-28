# フォーマッター設定

このプロジェクトでは [treefmt-nix](https://github.com/numtide/treefmt-nix) を使用して、複数のフォーマッターを管理しています。
設定値と実行依存の正本は [nix/treefmt.nix](../../nix/treefmt.nix) です。
設定ファイルは Nix store に生成し、project root には配置しません。

## 対象

| 言語/形式  | フォーマッター   | Nix の設定先                    |
| ---------- | ---------------- | ------------------------------- |
| Nix        | nixfmt           | `programs.nixfmt`               |
| JSON/YAML  | oxfmt            | `settings.formatter.oxfmt`      |
| Shell      | shfmt            | `programs.shfmt`                |
| PowerShell | PSScriptAnalyzer | `settings.formatter.powershell` |
| TOML       | Taplo            | `programs.taplo.settings`       |
| Lua        | StyLua           | `programs.stylua.settings`      |
| Markdown   | dprint           | `programs.dprint.settings`      |

PowerShell の静的解析設定は [PowerShell.Tests.ps1](../../scripts/powershell/tests/PowerShell.Tests.ps1) が所有します。

## 使用方法

```bash
nix fmt
nix fmt -- path/to/file.nix
nix fmt -- --fail-on-change
```

`nix develop` 内では `treefmt` も同じ設定で使用できます。
Windows では `task fmt` / `task fmt:check` が WSL の Nix を呼び出します。
`--fail-on-change` は整形したうえで変更があれば失敗します。
[pre-commit](../../.pre-commit-config.yaml) も同じコマンドを使い、CI は標準の `checks.<system>.treefmt` を実行します。
作業ファイルを書き換えない検査には `nix build .#checks.x86_64-linux.treefmt --no-link` を使います。

## 詳細

- [treefmt](treefmt.md): 設定生成・実行・エディター連携
- [Nix](nix.md)
- [Shell](shell.md)
- [Markdown](markdown.md)
- [TOML](toml.md)
- [PowerShell](powershell.md)
- [JSON/YAML](json-yaml.md)
- [Lua](lua.md)
