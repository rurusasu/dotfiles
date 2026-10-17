# Homebrew cask のトラブルシューティング

## download の再試行

`Fetching ...` で失敗した場合は `~/Library/Caches/Homebrew/downloads/*.incomplete` を手動削除せず、そのまま `nrs` を再実行します。nix-darwin の Homebrew Bundle が宣言済み formula/cask を収束させます。

## フルディスクアクセス

`zap` で `Please enable Full Disk Access for your terminal` と表示された場合は、
「システム設定 → プライバシーとセキュリティ → フルディスクアクセス」で、
実行元の端末アプリ（Ghostty から実行した場合は Ghostty）を有効にしてください。
一覧にない場合は「＋」から、実際に使っているアプリ本体を追加します。
Nix の Ghostty は `~/Applications/Home Manager Apps/Ghostty.app` です。
端末アプリを `⌘Q` で終了して開き直し、既にビルドした構成を反映し直します。

```sh
sudo /nix/var/nix/profiles/system/sw/bin/darwin-rebuild activate
```

このコマンドは flake 更新・再ビルドを行いません。反映が完了するまで
`/run/current-system` は旧世代を指すため、再開には上記の system profile を使います。
Home Manager の `Library/Application Support/discord` 作成が同時に拒否される場合も、
同じ実行元アプリへのフルディスクアクセスを確認してください。
「アプリ管理」だけを許可しても、このデータアクセスの許可にはなりません。

## WezTerm

WezTerm は Nix provider で管理します。旧 cask `wezterm@nightly` の
install/upgrade と Nix への自動移行はサポートしません。`nrs` で現在の
Nix package を反映してください。旧 package が残っている場合の扱いは
[旧 provider サポート終了](./package-management.md#macos-の旧-provider-サポート終了)
を参照してください。
