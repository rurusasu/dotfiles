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

## 旧 Comfy Desktop の Nix 出力

macOS の Comfy Desktop は Homebrew cask `comfy` に移しました。
新しい構成は旧 Nix package をビルドしないため、通常は `nrs` でそのまま反映できます。
Nix daemon へのフルディスクアクセスは追加しません。

以前の失敗で未登録の app bundle が Nix store に残っている場合、後の GC が
`chmod ... Comfy Desktop.app ... Operation not permitted` で停止することがあります。
この場合だけ、installer や build が動いていない状態で、
「アプリ管理」を許可した端末から一度だけ復旧します。
以下はエラーで確認した 1.1.7 の出力です。別の出力の場合は、エラーに表示された
Comfy Desktop の package 出力パスに置き換えてください。

```sh
comfy_store_path=/nix/store/62klm2k7aynh364jfn6ga0cfwyc7p31v-comfyui-desktop-1.1.7
nix path-info --json "$comfy_store_path"
```

**`"valid": false` と確認できた出力だけを対象にします。次のコマンドは、
失敗して残った指定出力の中身を削除します。** 有効な出力や別の store path には実行しません。

```sh
sudo --set-home "$(command -v nix)" --store local store delete "$comfy_store_path"
test ! -e "$comfy_store_path"
```

`--store local` は daemon に依頼せず、端末から起動した Nix で指定出力を削除します。
Nix の参照保護は維持し、`--ignore-liveness` や `--delete-closure` は使いません。
この旧出力の復旧は Nix の更新ごとに行う処理ではありません。

## WezTerm

WezTerm は Nix provider で管理します。旧 cask `wezterm@nightly` の
install/upgrade と Nix への自動移行はサポートしません。`nrs` で現在の
Nix package を反映してください。旧 package が残っている場合の扱いは
[旧 provider サポート終了](./package-management.md#macos-の旧-provider-サポート終了)
を参照してください。
