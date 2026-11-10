# macOS アプリの管理

アプリの package・有効化・設定は `nix/modules/` が所有します。Homebrew は使いません。
更新は `nix flake update`、反映は `./install.sh` です。

## Steam

公式の最新 DMG を `steam-darwin` input で取得し、`flake.lock` で内容を固定します。
アプリを変更せず Nix package に展開し、Home Manager がコピーします。
現在の公式 bootstrap は Intel バイナリのため Apple Silicon では Rosetta が必要です。
Steam 本体とゲームの更新データはユーザーの Library に保存され、bootstrap の lock とは別に更新されます。

## Google Drive

公式 DMG を `google-drive` input で固定し、nix-darwin の activation が公式 PKG を実行します。
root 所有の helper、File Provider、Google の updater も公式 installer が設定します。
DMG を Nix store に保存し、インストール先は `/Applications/Google Drive.app` です。
適用済みの package を記録し、同じ package の再反映で installer を繰り返しません。
Google の自己更新、ログイン状態、同期データ、macOS の権限承認は Nix store の管理外です。

新規環境では Google へのログインと File Provider の承認が必要です。
[Google 公式の導入手順](https://knowledge.workspace.google.com/admin/drive/set-up-drive-for-desktop-for-your-organization)と
[macOS の権限・File Provider](https://support.google.com/drive/answer/12178485)を参照してください。

## Home Manager のアプリ管理権限

アプリのコピーやユーザーデータへのアクセスを拒否された場合は、実行元の端末アプリに
「アプリ管理」または「フルディスクアクセス」を付与し、端末を終了して開き直してください。
ビルド済みの system profile を再反映する場合は次を実行します。

```sh
sudo /nix/var/nix/profiles/system/sw/bin/darwin-rebuild activate
```
