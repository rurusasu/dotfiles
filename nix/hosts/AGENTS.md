# nix/hosts: OS とホストの構成

- `default.nix`: 共通 OS 設定、timezone、Nix daemon、OS GC、Home Manager 接続。
- `darwin/default.nix`: nix-darwin、macOS アカウント・基盤設定。
- `linux/default.nix`: native NixOS / WSL の OS 基盤。native Linux では Hyprland も有効化する。
- `wsl/default.nix`: NixOS-WSL、GPU・フォント配布・portal・interop の OS 設定。
- ユーザーの基盤設定は `../home/common.nix`、アプリの OS 差分は `../modules/`。統合・Home Manager 単独 は `../home/default.nix` を同じように読み込む。
- Home Manager のユーザー名は `../home/settings.nix`、各 stateVersion は root の `flake.nix`。OS 構成の登録は `configurations.nix`、共通 Nix ポリシーは `../modules/nix/settings.nix`。
- アプリ固有の設定・サービス・activation・package factory は `../modules/` の対応する scope に置く。
