# 既定のログインシェル

NixOS / NixOS-WSL は、対象ユーザーのログインシェルに zsh を設定します。
`programs.zsh.enable` で zsh を導入し、ユーザーの `shell` option に反映します。
通常の `nrs` / インストール後、新しいログインセッションから有効になります。

macOS は `programs.zsh.enable` と Home Manager で zsh の設定を管理します。
既存アカウントのログインシェルを変更する独自 activation は実行しません。
Windows と standalone Home Manager / System Manager のログインシェルは変更しません。

## 検証

`nix build .#checks.<system>.nix-unit --no-link --no-write-lock-file` で
NixOS / WSL の zsh 導入・選択と、macOS の zsh 設定を検証します。
