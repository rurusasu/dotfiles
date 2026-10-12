# nix/modules: 再利用モジュール

## 管理対象

- `tools.nix`: Unix CLI の導入を一括管理する。Home Manager 標準の `programs.*.enable`、設定をユーザーが管理する CLI・標準 module のない CLI・LSP・プラグイン実行依存の `home.packages` をここに宣言する
- `browsers/dia/`: Dia の package 選択関数・公式バイナリの package 定義・更新用 candidate 情報
- `shells/powershell/psscriptanalyzer.nix`: formatter 用 PSScriptAnalyzer の package 定義
- `ai_agents/chatgpt/`: macOS の ChatGPT アプリを `home.packages` に直接導入し、標準 `programs.codex` の `package = null` で同梱 CLI の設定・context・rules・hooks を管理する。`mutableSettings` でアプリの設定追記を保持し、公式 desktop worktree cleanup を宣言する。Windows の導入は `windows/winget/packages.json`、ユーザー設定は chezmoi が所有する
- `fonts.nix`: Darwin / NixOS 共通のフォントパッケージと fontconfig の既定フォント
- `1password/`: nixpkgs の既存デスクトップ版を導入する。`default.nix` が Linux デスクトップ版、`ssh.nix` が公式 agent socket の `IdentityAgent` / `SSH_AUTH_SOCK` と activation 時の公開鍵取得、`sync-ssh-public-key.sh` が timeout・検証・既存鍵保持、`darwin-system.nix` が macOS システムのデスクトップ版を担当する。CLI 導入は `tools.nix`、Git signer / WSL interop の OS 固有設定は `nix/hosts/` に置く
- `git/`: Git 共通設定を `default.nix`、ghq の共通保存先を `ghq.nix`、既存の `git gtr` alias を `gtr.nix` にまとめる。Git / ghq の導入は `tools.nix`、署名コマンドと WSL の保存先は `nix/hosts/` が担当する
- `ssh.nix`: SSH の共通 Home Manager 設定。1Password agent の接続設定は `1password/ssh.nix` が担当する
- `discord/`: Home Manager 標準 `programs.discord` と macOS の native module staging。Darwin / native Linux から読み込み、WSL には導入しない
- `lazygit/`: Bash / Zsh の `lg` 連携。CLI の有効化は `tools.nix` が担当する
- `ai_agents/hermes/`: 公式 flake の Home Manager module と native gateway・CLI 設定・bootstrap manifest を管理する。`bootstrap.nix` が bootstrap の構築を担当する。CLI の有効化は `tools.nix`、gateway とサービス用依存はこの module に置く。upstream の依存 pin と既存データは維持する
- `shells/plugins/starship/`: Zsh 連携とプロンプト設定を `programs.starship.settings` で管理する。CLI の有効化は `tools.nix` が担当し、Home Manager が `starship.toml` を生成する
- `editors/nvim/`: Neovim の設定・プラグイン・Lua 配置。Neovim 本体と補助 CLI・LSP・プラグイン実行依存の導入は `tools.nix` が担当する
- `editors/orca/`: macOS / Linux 共通の Orca Editor Home Manager module と公式バイナリのパッケージ定義。バージョン・URL・ハッシュは `sources.json` に集約する
- `terminals/`: Ghostty / WezTerm の Home Manager 設定。各 `defaults.nix` を OS module の `sharedModules` から直接読み込む
- `herdr/`: 標準 `programs.herdr.settings` にキー設定を Nix で直接定義する。CLI の有効化は `tools.nix` が担当する
- `shells/zsh/`: zsh の補完プラグインと連携設定。CLI の有効化は `tools.nix`、履歴・alias・キー設定などは `nix/home/shells/zsh/` が担当する
- `shells/bash/`: Bash の初期化・ログイン設定。CLI の有効化は `tools.nix` が担当し、`nix/home/common.nix` から読み込む
- OS 固有の option・有効化・共通 module の配線は `nix/hosts/` が担当する。OS 別ディレクトリは置かない

## ルール

- ホスト依存が強い設定は `nix/hosts/*` に残す。
- Python のユーザー環境は `tools.nix` が導入する uv で管理する。Python interpreter の直接導入は行わず、Nix 内部専用の Python 依存はその module に置く。
- GitHub CLI は `tools.nix` の `home.packages` に `gh` を導入し、既存の `~/.config/gh/config.yml` はユーザーが管理する。
- CLI の PATH への導入は `tools.nix` に宣言し、各 module は設定・連携・package override を担当する。GUI・OS service・フォント・ビルド用依存はそれぞれの所有先に置く。
- 設定・サービスから絶対 store path で呼び出す専用の実行依存は、その module が管理する。zsh-patina の activate 連携もこの範囲に含む。
- ここでは複数ホストで再利用できる単位に分割する。
- Windows の WinGet 導入情報は `windows/winget/packages.json` に直接定義し、Unix module に Windows install metadata を置かない。
