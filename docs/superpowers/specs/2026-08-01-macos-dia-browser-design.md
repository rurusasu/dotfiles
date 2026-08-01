# macOS Browser Provider Design

## Goal

macOS では Arc をインストールせず、Dia をインストールする。Windows の Arc は現状のまま維持する。

## Design

パッケージカタログ `nix/packages/sets.nix` を唯一の変更対象とする。

- `arc-browser.support.darwin` を削除する。
- `arc-browser.winget` と `support.windows` は維持する。
- 既存の `dia-browser.support.darwin.cask = "thebrowsercompany-dia"` は変更しない。

`darwinCasks` はカタログの `support.darwin.cask` から生成されるため、これにより macOS の Homebrew cask から `arc` が除外され、Dia は引き続き含まれる。Windows の winget マッピングには影響しない。

## Verification

- カタログの Bats テストを実行する。
- `nix fmt -- --check` 相当の Nix フォーマット検証を行う。
- `git diff` で Arc の macOS 定義だけが削除され、Windows Arc と Dia の定義が保持されていることを確認する。
