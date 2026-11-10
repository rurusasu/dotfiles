# chezmoi/wsl: WSL ホストの設定例

- `.wslconfig.example` は控えめなリソース割り当ての例。
- 配布する設定の正本は `../dot_wslconfig`。chezmoi が Windows の `%USERPROFILE%/.wslconfig` へ配布する。
- 設定変更後は `wsl --shutdown` で WSL を停止し、次回起動時に読み直す。
- このサンプルディレクトリ自体は配布対象外。WSL 内の OS 設定は `nix/hosts/wsl/`、ユーザー向けアプリの WSL 連携は各 `nix/modules/` が所有する。
