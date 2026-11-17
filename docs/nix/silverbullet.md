# SilverBullet 試行サーバー

macOS の Home Manager は `pkgs.silverbullet` を使い、launchd の
`silverbullet-trial` エージェントを常駐させます。nix-darwin 統合と standalone
Home Manager の両方で有効になり、Linux/WSL には追加しません。

- URL: <http://127.0.0.1:3001>
- space: `~/silverbullet-trial/space`
- 標準出力・標準エラー: `~/silverbullet-trial/server.log`

`--single` で起動し、ログイン時の起動と終了時の再起動を launchd に任せます。
Home Manager の activation は起動前に space ディレクトリを作成します。
ノートの複製・移動は行いません。用意済みの試行ファイルはそのまま利用します。

`services.silverbullet-trial.directory` で試行ディレクトリ、`package` で
パッケージを変更できます。停止する場合は次を設定して再適用します。

```nix
services.silverbullet-trial.enable = lib.mkForce false;
```

macOS で通常の `./install.sh` を実行して反映後、上記 URL を開いて起動を確認します。
同じ space を Obsidian の vault として開き、`.obsidian/` の設定ファイルが
SilverBullet の一覧に現れないことと、両アプリ間で Markdown の編集が反映されることを
実機で確認します。2.12.1 の Linux での一時 space 起動確認では `.obsidian/` は
一覧に出ず、HTTP による直接取得も 404 でした。macOS の launchd 起動と両アプリの
編集反映は別途実機で確認します。追加の除外設定は入れていません。
