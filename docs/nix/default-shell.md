# 既定のログインシェル

`nix/hosts` の macOS、native NixOS、NixOS-WSL は、dotfiles の対象ユーザーに zsh を設定します。
ターミナルアプリ自体は変更しません。Windows の設定と、standalone Home Manager /
Ubuntu・Debian の System Manager は対象外です。

macOS は OS 付属の `/bin/zsh` を使い、インストール処理や `/etc/shells` の管理を追加しません。
既存の Home Manager / nix-darwin によるパッケージ・ユーザー設定はそのままです。
NixOS / WSL は共有 system module が zsh を取得・ビルドしてからユーザーの `shell` option を反映します。

macOS は既存ローカルアカウントの `UserShell` だけを更新します。既に `/bin/zsh` なら変更せず、
実行ファイル・登録・対象ユーザーの確認に失敗した場合は切り替えません。変更後も設定値を読み直します。
OS 付属の `/bin/zsh` が予期せず欠けている場合は安全に停止し、別のシェルを自動導入しません。
設定はすべて Nix 内で管理し、独立した shell script は配布しません。

macOS の `users.users.<name>.shell` は `users.knownUsers` に属するアカウントだけを更新します。
既存の管理者アカウントをそのリストへ追加しないよう upstream が注意しているため、
この構成では標準 option で `/bin/zsh` の選択を宣言し、既存アカウントの反映だけを
`configuration.nix` の短い activation で補います。

反映は通常の `nrs` / `install.sh` の実行後、新しいログインセッションから有効になります。
既存のシェルセッションは切り替わりません。ターミナルに独自の起動コマンドを指定している
場合、その設定がログインシェルより優先されます。

## macOS の既存設定

- 管理者アカウントを `users.knownUsers` に追加しません。UID、グループ、パスワードを変更しません。
- `/etc/shells` は読み取りによる確認だけを行い、既存エントリーを変更しません。
- `/bin/zsh` は OS のファイルなので、Nix generation の削除・GC でログインシェルが消えることはありません。

## テスト

`nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file` が NixOS / WSL の
zsh 導入・選択と、macOS の `/bin/zsh` 選択・activation 配線を検証します。
`nix build .#checks.<system>.darwin-default-shell --no-link --no-write-lock-file` は
実際に Nix が生成する activation を隔離したコマンド境界で実行し、対象ユーザー、実行ファイル欠損時の拒否、
冪等性、失敗伝播、変更後の読み直しを検証します。`task test:nix` と Linux/macOS CI に含まれます。
このテストは実機のアカウントを変更しません。
