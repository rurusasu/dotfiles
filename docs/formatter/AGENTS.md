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
