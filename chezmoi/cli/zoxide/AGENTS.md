# chezmoi/cli/zoxide: zoxide 環境設定

## 編集対象

- `env`（Windows 向けの参照用環境変数）

## 変更ルール

- 除外ディレクトリは誤ジャンプ防止目的に限定する。
- Unix の導入は `nix/modules/shells/plugins/zoxide.nix`、shell integration は `nix/home/shells/plugins/zoxide.nix`、WSL の環境変数は `nix/hosts/x86_64-linux/wsl/home.nix` で管理する。
- Windows の PowerShell は `chezmoi/shells/Microsoft.PowerShell_profile.ps1`、Bash は `chezmoi/shells/zoxide.bash` で管理する。
