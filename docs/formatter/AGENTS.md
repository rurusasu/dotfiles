# docs/formatter: formatter 設定変更ガイド

## source of truth

- `.treefmt.toml`
- `nix/flake/treefmt.nix`

## 変更手順

1. `.treefmt.toml` に対象言語の formatter 設定を追加・修正する。
2. `nix/flake/treefmt.nix` で formatter バイナリ提供設定を更新する。
3. 必要ならこの `docs/formatter/` の各言語ドキュメントを更新する。

## 実行コマンド

```bash
nix fmt
treefmt --check
```

## ルール

- formatter の追加は「適用対象ファイル」と「導入理由」をセットで残す。
- treefmt-nix 未対応ツールはカスタム定義で明示的に管理する。

## chezmoi テンプレートの境界

- treefmt は chezmoi 展開前のソースを解析する。`{{ ... }}` を含むファイルでも、展開前の構文が対象言語として成立するもの（Lua など）は通常どおり formatter の対象にする。
- 展開前には有効な JSON にならないテンプレートは、oxfmt の対象から除外する。現在の対象と除外理由は `.treefmt.toml` の `formatter.oxfmt.excludes` を source of truth とする。
- 除外はテストを省略する指定ではない。対象ファイルを検証するテストは `chezmoi execute-template` で OS とデータを与えてレンダリングしてから、JSON などの実構文を解析する。
- format gate はソースの整形、Chezmoi CI はレンダリング後の構文・意味の検証を担当する。どちらか一方をもう一方の代替として扱わない。
