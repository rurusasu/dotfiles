# nix/modules: 再利用モジュール

## 管理対象

- `host/`: 共通システム設定
- `wsl/`: WSL 固有調整
- `fonts.nix`: Darwin / NixOS 共通のフォントパッケージと fontconfig の既定フォント
- `lsp.nix`: 全エディタ共通の言語サーバー・整形ツール。通常の PATH に導入する
- `cursor/`: Cursor の LSP 設定と、既存の非 LSP 設定を保持する Home Manager 設定
- `nvim/`: Darwin / NixOS の Home Manager に読み込む Neovim とプラグインの設定
- `darwin/`, `nixos/`: OS 固有の option と共通 module の読み込み

## ルール

- ホスト依存が強い設定は `nix/hosts/*` に残す。
- ここでは複数ホストで再利用できる単位に分割する。
