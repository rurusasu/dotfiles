# 既定のログインシェル

NixOS / NixOS-WSL は、対象ユーザーのログインシェルに zsh を設定します。
`programs.zsh.enable` で zsh を導入し、ユーザーの `shell` option に反映します。
通常の `nrs` / インストール後、新しいログインセッションから有効になります。

macOS は `programs.zsh.enable` と Home Manager で zsh の設定を管理します。
既存アカウントのログインシェルを変更する独自 activation は実行しません。
Windows と standalone Home Manager のログインシェルは変更しません。

## WSL の Git プロンプト

WSL では `programs.starship.wslIntegration.enable` により、Windows ドライブの
Git 状態を Windows 版 Starship で取得します。Windows 側は
`windows/winget/packages.json` の `Starship.Starship` が管理します。

Bash / Zsh の起動時に `starship.exe` の場所を一度だけ解決し、絶対パスの
ラッパーを通して呼び出します。これにより、プロンプト更新ごとの Windows
ドライブ上の PATH 探索を省きます。Git の表示内容と終了コードは維持します。
Windows 側の導入先を変更した場合は、新しいシェルを開いて再解決してください。

WSL の Zsh では `programs.starship.asyncZsh.enable` も有効にします。
入力を先に受け付け、Starship の左プロンプトを計算後に更新します。
初回やコマンド実行直後は短い `[updating]` 表示になり、同じ場所での空 Enter は
直前の表示を使いながら再計算します。Git 情報の計算は従来と同じ設定で行います。

非同期処理には nixpkgs の `pure-prompt` に同梱された `zsh-async` ライブラリを
使用します。Starship の設定・色・終了コードと、右プロンプト・補完・
ハイライトは維持します。ディレクトリや環境の切替後に古い結果を適用せず、
処理が失敗した場合は通常の同期表示へ戻ります。
ライブラリが内部で呼ぶ `cat` は Nix の絶対パスに置き換え、OS の
`/bin` や `/usr/bin` に依存しないようにします。

## 検証

`nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file` で
NixOS / WSL の zsh 導入・選択と、macOS の zsh 設定を検証します。
