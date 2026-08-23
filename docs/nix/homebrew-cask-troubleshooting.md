# Homebrew cask のトラブルシューティング

## download の再試行

`Fetching ...` で失敗した場合は `~/Library/Caches/Homebrew/downloads/*.incomplete` を手動削除せず、そのまま `nrs` を再実行します。nix-darwin の Homebrew Bundle が宣言済み formula/cask を収束させます。

## WezTerm nightly

`wezterm@nightly` は nix-darwin の Homebrew cask として宣言され、通常の
Homebrew Bundle の install/upgrade 対象になります。個別の手動インストーラーや
cask 定義の編集は不要です。

状態確認や単体での再試行が必要な場合は、次を使います。

```zsh
brew info --cask wezterm@nightly
brew upgrade --cask --greedy wezterm@nightly
```

`nrs` 全体で再適用する場合は、リポジトリの通常の macOS 反映手順を使います。
