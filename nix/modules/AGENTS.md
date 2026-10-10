# nix/modules: 再利用モジュール

## 管理対象

- `codex/`: ChatGPT アプリ付属 CLI の設定を担当し、標準 `programs.codex` で Unix の設定・context・rules・hooks を管理する。`mutableSettings` でアプリの設定追記を保持し、公式 desktop worktree cleanup を宣言する。Windows は chezmoi が所有する
- `fonts.nix`: Darwin / NixOS 共通のフォントパッケージと fontconfig の既定フォント
- `1password/`: nixpkgs の既存 CLI / デスクトップ版を直接導入する。`default.nix` が Home Manager の CLI と Linux デスクトップ版、`ssh.nix` が公式 agent socket の `IdentityAgent` / `SSH_AUTH_SOCK` と activation 時の公開鍵取得、`sync-ssh-public-key.sh` が timeout・検証・既存鍵保持、`darwin-system.nix` が macOS システムのデスクトップ版、`windows-install.nix` が Windows 配布・検証 metadata を担当する。Git signer / WSL interop の OS 固有設定は `nix/hosts/` に残す
- `git/`: Git 共通設定と標準 program 有効化を `default.nix`、ghq の導入・共通保存先を `ghq.nix`、既存の `git gtr` alias を `gtr.nix`、Git / ghq の Windows 配布・検証 metadata を `windows-install.nix` にまとめる。署名コマンドと WSL の保存先は `nix/hosts/` が担当する
- `ssh.nix`: SSH の共通 Home Manager 設定。1Password agent の接続設定は `1password/ssh.nix` が担当する
- `discord/`: Home Manager 標準 `programs.discord` と macOS の native module staging。Darwin / native Linux から読み込み、WSL には導入しない
- `starship/`: Home Manager 標準 `programs.starship` と Zsh 連携。Discord / Starship の Windows 配布 metadata も各 module の `windows-install.nix` に置く
- `lazygit/`: Home Manager 標準 `programs.lazygit` と Bash / Zsh の `lg` 連携。Windows 配布・検証 metadata は同じ module の `windows-install.nix` が担当する
- `lsp.nix`: 全エディタ共通の言語サーバー・整形ツール。通常の PATH に導入する
- `dsh.nix`: Numtide の `llm-agents` flake から DeepSeek Harness を導入する。キャッシュを保つため upstream の nixpkgs を変更しない
- `hermes-agent/`: 公式 flake の Home Manager module と native gateway・bootstrap manifest を管理する。`nix/home/common.nix` が読み込み、CLI / gateway を常に有効化する。upstream の依存 pin と既存データは維持する
- `shells/plugins/`: fzf / zoxide / eza / bat / ripgrep の Home Manager program 有効化。ユーザー設定は `nix/home/shells/plugins/`、WSL 固有設定は `nix/hosts/x86_64-linux/wsl/home.nix` が担当する
- `editors/nvim/`: Darwin / NixOS の Home Manager に読み込む Neovim とプラグインの設定
- `editors/orca/`: macOS / Linux 共通の Orca Editor Home Manager module と公式バイナリのパッケージ定義。バージョン・URL・ハッシュは `sources.json` に集約する。Windows 配布 metadata は `nix/packages/install/` が担当する
- `terminals/`: Ghostty / WezTerm の Home Manager 設定。各 `defaults.nix` を OS module の `sharedModules` から直接読み込む
- `herdr/`: Home Manager 標準 `programs.herdr` による導入とキー設定。`default.nix` と `config.toml` を同じ module にまとめ、Unix の外部 installer は使わない
- `shells/zsh/`: zsh の導入と補完プラグインの定義。`default.nix` を OS module の `sharedModules` と standalone Home Manager から読み込む。履歴・alias・キー設定などは `nix/home/shells/zsh/` が担当する
- `shells/bash/`: Bash の Home Manager 有効化・初期化・ログイン設定。`nix/home/common.nix` から読み込む
- OS 固有の option・有効化・共通 module の配線は `nix/hosts/` が担当する。OS 別ディレクトリは置かない

## ルール

- ホスト依存が強い設定は `nix/hosts/*` に残す。
- ここでは複数ホストで再利用できる単位に分割する。
