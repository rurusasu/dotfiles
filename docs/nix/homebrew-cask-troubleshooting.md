# Homebrew cask のトラブルシューティング

## download の再試行

`Fetching ...` で失敗した場合は `~/Library/Caches/Homebrew/downloads/*.incomplete` を手動削除せず、そのまま `nrs` を再実行します。nix-darwin の Homebrew Bundle が宣言済み formula/cask を収束させます。

## WezTerm

WezTerm は Nix provider で管理します。旧 cask `wezterm@nightly` の
install/upgrade と Nix への自動移行はサポートしません。`nrs` で現在の
Nix package を反映してください。旧 package が残っている場合の扱いは
[旧 provider サポート終了](./package-management.md#macos-の旧-provider-サポート終了)
を参照してください。
