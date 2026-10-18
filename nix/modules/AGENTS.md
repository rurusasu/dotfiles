# nix/modules: 再利用モジュール

## 管理対象

- `tools.nix`: Unix CLI の PATH への導入を管理する。CLI の Home Manager 標準 `programs.*.enable`、設定をユーザーが管理する CLI・標準 module のない CLI・LSP・プラグイン実行依存の `home.packages` をここに宣言する。ChatGPT / Orca / Ghostty / WezTerm / Discord と `nativeDesktop` の既存 GUI 選択子は現時点では残るが、新しい GUI の導入はここに追加しない
- `desktop.nix`: Linux / WSLg GUI の導入。属性セットの `linuxDesktop` が Chrome / Nautilus（Files）/ Obsidian / 1Password GUI と x86_64 の ComfyUI Desktop を宣言し、`wslDesktop` が `linuxDesktop` を imports して Spotify / Signal を追加する
- `desktop-darwin.nix`: Darwin system GUI の導入を宣言する通常の module。Dia / Obsidian / Raycast / 1Password GUI / ComfyUI Desktop を管理する
- `comfyui/`: ComfyUI Desktop の公式 macOS / Linux バイナリの package 定義。バージョン・ビルド固定 URL・ハッシュは `package.nix` に集約する。モデル・カスタムノード・実行環境は Desktop が管理するユーザーデータとして扱う
- `browsers/dia/`: Dia の package 選択関数・公式バイナリの package 定義・更新用 candidate 情報
- `shells/powershell/psscriptanalyzer.nix`: formatter 用 PSScriptAnalyzer の package 定義
- `ai_agents/chatgpt/`: `tools.nix` が Darwin / native NixOS のアプリを `home.packages`、同梱 CLI を標準 `programs.codex.package` で宣言する。専用 `chatgpt-nixpkgs` input を利用する `packages.nix` を両 OS で共有し、同ディレクトリの `desktop.nix` が Linux のキャッシュ cleanup を標準 `systemd.user.tmpfiles.rules` で管理する。WSL は同じ Linux 同梱 CLI を選び、GUI アプリは直接配布しない。標準 `programs.codex` で設定・context・rules・hooks を管理する。`mutableSettings` でアプリの設定追記を保持し、公式 desktop worktree cleanup を宣言する。Windows の導入は `windows/winget/packages.json`、ユーザー設定は chezmoi が所有する
- `fonts.nix`: Darwin / NixOS 共通のフォントパッケージと fontconfig の既定フォント
- `fonts/gtk.nix`: Linux GUI の GTK 3 / 4 と設定ポータルの既定フォント。dconf service の登録は NixOS host が担当する
- `1password/`: CLI の導入は `tools.nix`、Linux / WSLg GUI は `desktop.nix`、Darwin system GUI は `desktop-darwin.nix`。`default.nix` が SSH 設定を読み込み、`ssh.nix` が公式 agent socket の `IdentityAgent` / `SSH_AUTH_SOCK` と activation 時の公開鍵取得、`sync-ssh-public-key.sh` が timeout・検証・既存鍵保持を担当する。Git signer / Windows の `op.exe` を使う WSL interop の OS 固有設定は `nix/hosts/` に置く
- `git/`: Git 共通設定を `default.nix`、ghq の共通保存先を `ghq.nix`、既存の `git gtr` alias を `gtr.nix` にまとめる。Git / ghq の導入は `tools.nix`、署名コマンドと WSL の保存先は `nix/hosts/` が担当する
- `ssh.nix`: SSH の共通 Home Manager 設定。1Password agent の接続設定は `1password/ssh.nix` が担当する
- `discord/`: Home Manager 標準 `programs.discord` と macOS の native module staging。Darwin / native Linux から読み込み、WSL には導入しない
- `lazygit/`: Bash / Zsh の `lg` 連携。CLI の有効化は `tools.nix` が担当する
- `ai_agents/hermes/`: 公式 flake の Home Manager module と native gateway・CLI 設定・bootstrap manifest を管理する。`bootstrap.nix` が bootstrap の構築を担当する。CLI の有効化は `tools.nix`、gateway とサービス用依存はこの module に置く。upstream の依存 pin と既存データは維持する
- `shells/plugins/starship/`: Zsh 連携とプロンプト設定を `programs.starship.settings` で管理する。CLI の有効化は `tools.nix` が担当し、Home Manager が `starship.toml` を生成する
- `editors/nvim/`: Neovim の設定・プラグイン・Lua 配置。Neovim 本体と補助 CLI・LSP・プラグイン実行依存の導入は `tools.nix` が担当する
- `editors/orca/`: macOS / Linux 共通の Orca Editor の公式バイナリ定義。導入は `tools.nix` が担当する。バージョン・URL・ハッシュは `package.nix` に集約する
- `terminals/`: Ghostty / WezTerm の Home Manager 設定。各 `defaults.nix` を OS module の `sharedModules` から直接読み込む
- `herdr/`: 標準 `programs.herdr.settings` にキー設定を Nix で直接定義する。CLI の有効化は `tools.nix` が担当する
- `shells/zsh/`: zsh の補完プラグインと連携設定。CLI の有効化は `tools.nix`、履歴・alias・キー設定などは `nix/home/shells/zsh/` が担当する
- `shells/bash/`: Bash の初期化・ログイン設定。CLI の有効化は `tools.nix` が担当し、`nix/home/common.nix` から読み込む
- OS 固有の option・有効化・共通 module の配線は `nix/hosts/` が担当する。OS 別ディレクトリは置かない

## ルール

- ホスト依存が強い設定は `nix/hosts/*` に残す。
- Python のユーザー環境は `tools.nix` が導入する uv で管理する。Python interpreter の直接導入は行わず、Nix 内部専用の Python 依存はその module に置く。
- GitHub CLI は `tools.nix` の `home.packages` に `gh` を導入し、Darwin の host 連携用 system package も `tools.nix` の `darwin` に残す。既存の `~/.config/gh/config.yml` はユーザーが管理する。
- CLI の PATH への導入は `tools.nix` に宣言し、各 module は設定・連携・package override を担当する。Linux / WSLg GUI の導入は `desktop.nix`、Darwin system GUI は `desktop-darwin.nix` に置く。既存の GUI 選択子を理由に `tools.nix` へ新しい GUI を追加しない。OS service・フォント・ビルド用依存はそれぞれの所有先に置く。
- 設定・サービスから絶対 store path で呼び出す専用の実行依存は、その module が管理する。zsh-patina の activate 連携もこの範囲に含む。
- ここでは複数ホストで再利用できる単位に分割する。
- Windows の WinGet 導入情報は `windows/winget/packages.json` に直接定義し、Unix module に Windows install metadata を置かない。
