# nix/modules: 再利用モジュール

## 管理対象

- `wsl/`: WSL 固有調整
- `fzf.nix`: fzf のパッケージ導入と共通既定値。Bash/Zsh の独自 widget は各シェル設定が担当する
- `fonts.nix`: Darwin / NixOS 共通のフォントパッケージと fontconfig の既定フォント
- `lsp.nix`: 全エディタ共通の言語サーバー・整形ツール。通常の PATH に導入する
- `nvim/`: Darwin / NixOS の Home Manager に読み込む Neovim とプラグインの設定
- `terminals/`: Ghostty / WezTerm の Home Manager 設定。各 `defaults.nix` を OS module の `sharedModules` から直接読み込む
- `shells/zsh/`: zsh の導入と共通設定。`default.nix` を OS module の `sharedModules` と standalone Home Manager から読み込む
- `darwin/`, `nixos/`: OS 固有の option と共通 module の読み込み

## ルール

- ホスト依存が強い設定は `nix/hosts/*` に残す。
- ここでは複数ホストで再利用できる単位に分割する。
