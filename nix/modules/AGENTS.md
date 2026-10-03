# nix/modules: 再利用モジュール

## 管理対象

- `host/`: 共通システム設定
- `wsl/`: WSL 固有調整
- `fonts.nix`: Darwin / NixOS 共通のフォントパッケージと fontconfig の既定フォント
- `nvim/`: Darwin / NixOS の Home Manager に読み込む Neovim とプラグインの設定
- `darwin/`, `nixos/`: OS 固有の option と共通 module の読み込み

## ルール

- ホスト依存が強い設定は `nix/hosts/*` に残す。
- ここでは複数ホストで再利用できる単位に分割する。
