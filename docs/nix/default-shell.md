# 既定のログインシェル

`nix/hosts` の macOS、native NixOS、NixOS-WSL は、dotfiles の対象ユーザーに zsh を設定します。
ターミナルアプリ自体は変更しません。Windows の設定と、standalone Home Manager /
Ubuntu・Debian の System Manager は対象外です。

Nix が zsh を含む構成を取得・ビルドしてから activation を実行するため、zsh が未導入でも
先に用意されます。NixOS はユーザーの `shell` option、macOS は既存のローカルアカウントの
`UserShell` だけを更新します。既に同じシェルなら変更せず、実行ファイル・登録・ユーザーの
確認に失敗した場合は切り替えません。macOS は変更後も設定値を読み直します。

反映は通常の `nrs` / `install.sh` の実行後、新しいログインセッションから有効になります。
既存のシェルセッションは切り替わりません。ターミナルに独自の起動コマンドを指定している
場合、その設定がログインシェルより優先されます。

## macOS の既存設定と復旧

- 管理者アカウントを `users.knownUsers` に追加しません。UID、グループ、パスワードを変更しません。
- `/etc/shells` に独自の内容がある場合、nix-darwin は既存ファイル保護により反映を停止することがあります。
  既存エントリーを確認し、必要なシェルを Nix 設定へ移してから再実行してください。自動上書きはしません。
- macOS のログインシェルは具体的な Nix store の zsh を参照します。この変更より前の generation
  へ rollback しても Directory Services の値は元に戻りません。rollback・generation 削除・GC の
  前に、対象ユーザーで `chsh -s /bin/zsh` を実行して macOS 標準シェルへ戻してください。
  rollback 後は現在のシェルが `/etc/shells` から外れ、通常の `chsh` が拒否する場合があります。
  その場合は利用可能な管理者セッションから、対象のローカルユーザー名を明示して
  `sudo /usr/bin/chsh -l /Local/Default -s /bin/zsh <target-user>` で復旧してください。
  または、対象の zsh を含む generation を保持してこの構成を再反映します。

## テスト

`nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file` が各 host の
zsh 有効化・インストール・対象ユーザーへの選択を検証します。
`python3 -m unittest discover -s tests/python -p test_darwin_default_shell.py -v` は
隔離したコマンド境界で、対象ユーザー、導入前の拒否、冪等性、失敗伝播、変更後の読み直しを検証します。
このテストは実機のアカウントを変更しません。
