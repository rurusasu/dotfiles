# chezmoi/cli/ripgrep: rg デフォルト設定

## 編集対象

- `config` -> Windows の `~/.config/ripgrep/config`
- Unix の設定は `nix/home/shells/plugins/ripgrep.nix` の `programs.ripgrep.arguments` が管理する。

## 変更ルール

- `--hidden` や `--glob` 変更時は検索結果への影響を確認する。
- チーム共通で困るオプションは追加しない。
