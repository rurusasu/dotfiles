# SilverBullet

## macOS アプリ

Apple Silicon の macOS では `programs.silverbullet.enable` により公式の
SilverBullet Desktop を導入します。nixpkgs の `pkgs.silverbullet` はサーバー版のみのため、
デスクトップ版は公式 DMG のバージョンと SHA-256 を `nix/modules/silverbullet/package.nix`
に固定します。更新時は同ファイルの両方を更新します。

Home Manager が通常 `~/Applications/Home Manager Apps/SilverBullet.app` にコピーし、
Mac のアプリ一覧から `SilverBullet` を起動できます。初回起動時は `New/Open Space` から
`~/lifelog` を選ぶと、既存の lifelog vault を開けます。
デスクトップ版はサーバーを常駐させずにローカルのフォルダーを開けます。

## 試行サーバー

macOS の Home Manager は `pkgs.silverbullet` を使い、launchd の
`silverbullet-trial` エージェントを常駐させます。nix-darwin 統合と standalone
Home Manager の両方で有効になり、Linux/WSL には追加しません。

- URL: <http://127.0.0.1:3001>
- space: `~/lifelog`
- 標準出力・標準エラー: `~/silverbullet-trial/server.log`

`--single` で起動し、ログイン時の起動と終了時の再起動を launchd に任せます。
Home Manager は Google Drive 内の既存の lifelog vault を指す `~/lifelog` シンボリックリンクを
管理し、サーバーにはこの ASCII パスを渡します。Google Drive の同期先にある既存の
vault を利用するため、ノートの複製・移動・新規 space の作成は行いません。
activation は起動前にログ用ディレクトリを作成します。

`services.silverbullet-trial.space` でサーバーが開くフォルダー、`directory` でログ用ディレクトリ、
`package` でサーバーパッケージを変更できます。停止する場合は次を設定して再適用します。

```nix
services.silverbullet-trial.enable = lib.mkForce false;
```

macOS で通常の `./install.sh` を実行して反映後、上記 URL を開いて起動を確認します。
同じ space を Obsidian の vault として開き、`.obsidian/` の設定ファイルが
SilverBullet の一覧に現れないことと、両アプリ間で Markdown の編集が反映されることを
実機で確認します。2.12.1 の Linux での一時 space 起動確認では `.obsidian/` は
一覧に出ず、HTTP による直接取得も 404 でした。macOS では Desktop の起動・署名検証、
launchd の稼働と HTTP 200 応答を実機で確認済みです。両アプリの編集反映は別途確認します。
追加の除外設定は入れていません。
