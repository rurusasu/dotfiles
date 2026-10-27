# treefmt 設定

[treefmt-nix](https://github.com/numtide/treefmt-nix) で formatter の設定と実行依存を管理します。
正本は [nix/treefmt.nix](../../nix/treefmt.nix) です。
このファイルは treefmt 専用の Nix モジュールで、`programs` と `settings` を直接宣言します。
[nix/defaults.nix](../../nix/defaults.nix) の `perSystem.treefmt.imports` が読み込み、
PowerShell 用の固定済み source を module 引数で渡します。
開発シェルも同じ `perSystem` で `inputsFrom = [ config.treefmt.build.devShell ];` を使い、
treefmt の実行環境に statix と deadnix を追加します。

## 設定の流れ

Nix の設定値から treefmt と各 formatter の設定を Nix store に生成します。
treefmt の wrapper が設定ファイルと実行バイナリの絶対パスを渡すため、
project root に生成物を配置する必要はありません。

- StyLua: `programs.stylua.settings` から TOML を生成し、`--config-path` で渡します。
- Taplo: `programs.taplo.settings` から TOML を生成し、`--config` で渡します。
- dprint: `programs.dprint.settings` から JSON を生成し、`--config` で渡します。
- oxfmt: `pkgs.formats.json` で JSON を生成し、`settings.formatter.oxfmt.options` から `--config` で渡します。
- PowerShell: nixpkgs の PowerShell 拡張機能に同梱された PSScriptAnalyzer を Nix store から import します。

Markdown は dprint が担当し、oxfmt の対象は JSON/YAML に限定します。
dprint の Markdown プラグインも nixpkgs から提供するため、整形中のダウンロードは不要です。

## 実行

```bash
# 全対象を整形
nix fmt

# 特定ファイルを整形
nix fmt -- path/to/file.nix

# 整形による変更が発生したら失敗
nix fmt -- --fail-on-change

# dev shell でも同じ wrapper を使う
nix develop
treefmt path/to/file.nix
```

Windows では `task fmt` が WSL の Nix を呼び出します。
`task fmt:check` と pre-commit は `nix fmt -- --fail-on-change` を利用します。
これは対象ファイルを整形したうえで、変更があれば失敗するコマンドです。
作業ファイルを書き換えずに検査する場合は、下記の Nix check を使います。
CI は `nix flake check` に含まれる同じ check を実行します。
Nix が提供する wrapper を使い、設定を持たない単独の treefmt を直接呼ばないでください。

## エディター

ファイルを指定できるエディターでは `nix develop` 内の `treefmt` を使用します。
各言語の formatter を直接起動する拡張機能は、treefmt-nix の設定を自動では読みません。
同じ設定を適用するには、生成された設定パスを明示するか treefmt を使うタスクを設定します。
未保存のバッファは `treefmt --stdin path/to/file.json` で渡せます。

## 検証

```bash
nix build .#checks.x86_64-linux.treefmt --no-link --no-write-lock-file
nix build .#checks.x86_64-linux.powershell-formatter --no-link --no-write-lock-file
```

treefmt-nix の flake-parts module が `formatter.<system>` と `checks.<system>.treefmt` を自動公開します。
独自の `build.check` は定義せず、標準 check がソースのコピーを整形して差分がないことを検証します。
`powershell-formatter` check は空の HOME と宣言済みの依存で PowerShell の整形・BOM 補完・冪等性を検証します。
chezmoi の未展開 JSON テンプレートの除外理由と semantic test は [AGENTS.md](AGENTS.md) を参照してください。

## 参照

- [treefmt](https://github.com/numtide/treefmt)
- [treefmt-nix](https://github.com/numtide/treefmt-nix)
