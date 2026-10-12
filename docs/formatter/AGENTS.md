# docs/formatter: formatter 設定変更ガイド

## source of truth

- `nix/formatter.nix`: formatter の設定値、対象・除外、バイナリと実行依存。
- treefmt-nix が設定を Nix store に生成し、wrapper が各 formatter に設定パスを渡す。
- project root に formatter の設定ファイルを二重管理しない。

## 変更手順

1. `nix/formatter.nix` の `treefmt.programs.*.settings` または生成用の属性セットを更新する。
2. 対象・除外や実行依存が変わる場合は同じ module の宣言を更新する。
3. 必要ならこの `docs/formatter/` の各言語ドキュメントを更新する。

## 実行コマンド

```bash
nix fmt
nix fmt -- --fail-on-change
```

`nix develop` 内の `treefmt` も同じ生成済み設定を参照する。
Windows の公開入口は WSL 経由の `task fmt` / `task fmt:check` とする。

## ルール

- formatter の追加は「適用対象ファイル」と「導入理由」をセットで残す。
- treefmt-nix 未対応ツールはカスタム定義で明示的に管理する。
- Markdown は dprint、JSON/YAML は oxfmt が担当し、同じファイルを二重整形しない。
- dprint プラグインは Nix の依存として提供し、整形中にネットワーク取得しない。

## chezmoi テンプレートの境界

- treefmt は chezmoi 展開前のソースを解析する。`{{ ... }}` を含むファイルでも、展開前の構文が対象言語として成立するもの（Lua など）は通常どおり formatter の対象にする。
- 展開前には有効な JSON にならないテンプレートは、oxfmt の対象から除外する。現在の対象と除外理由は `nix/formatter.nix` の `treefmt.settings.formatter.oxfmt.excludes` を source of truth とする。
- 除外はテストを省略する指定ではない。対象ファイルを検証するテストは `chezmoi execute-template` で OS とデータを与えてレンダリングしてから、JSON などの実構文を解析する。
- format gate はソースの整形、Chezmoi CI はレンダリング後の構文・意味の検証を担当する。どちらか一方をもう一方の代替として扱わない。
