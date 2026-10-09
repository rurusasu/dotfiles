# nix/hosts/x86_64-linux/wsl: NixOS WSL ホスト設定

## 管理対象

- `default.nix`
- `configuration.nix`
- `integration.nix`: WSLg・Windows interop・1Password・Docker などのシステム連携
- `home.nix`: WSL 固有の Home Manager 設定・パッケージ選択・ユーザーサービス
- `op-ssh-sign-wsl`: Windows の署名コマンドと WSL のパス・入出力を接続する

`default.nix` が entrypoint であり、`configuration.nix` を import する。WSL 固有の option は
`configuration.nix` に置く。

## ルール

- WSL 固有設定のみ置く。
- WSL のシステム連携は `integration.nix`、NixOS 共通設定は `nix/hosts/shared/nixos/platform.nix` に置く。
