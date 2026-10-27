# nix/modules: 再利用モジュール

## 管理対象

- アプリごとの module: 設定・package override・生成・連携と導入・専用の実行依存をまとめる。enable・単純な package list・単一代入だけなら `nix/defaults.nix` の必要な構成へ直接書く
- `browsers/dia/`: `package.nix` は `inputs.dia` を使う純粋な Darwin package factory。`default.nix` は型付き `programs.dia` と導入を管理し、構成側で有効化する
- `browsers/chrome/`: 標準 `programs.chromium` の固有設定と package factory。WSL の日本語 locale / fcitx 連携を管理する
- `shells/powershell/psscriptanalyzer.nix`: formatter 用 PSScriptAnalyzer の package 定義
- `ai_agents/chatgpt/`: ChatGPT と同梱 Codex CLI の package 選択・導入・設定を管理する。共通 nixpkgs の `pkgs.chatgpt.override { codex = null; }` と upstream の macOS 署名保持を利用する。`codex` は `pkgs.linkFarm` で `bin/codex`・`bin/codex-code-mode-host` と Linux の `bin/bwrap` を提供する。Darwin / native・standalone Linux はアプリと同梱 CLI、WSL は同じ Linux package の CLI へのリンクだけを導入する。`default.nix` が `programs.chatgpt.enable` / `programs.codex.enable` に従い導入・設定を管理する。`package.nix` は同梱 CLI へのリンクを作る通常の factory で、標準 `programs.codex.package = null` により config を管理する。`mutableSettings` でアプリの設定追記を保持し、公式 desktop worktree cleanup を宣言する。Windows の導入は `windows/winget/packages.json`、ユーザー設定は chezmoi が所有する
- `fonts/settings.nix`: Darwin / NixOS / Home Manager 共通のフォントパッケージと fontconfig の値を返す通常の関数
- `fonts/`: `default.nix` が共通の Home Manager fontconfig と Linux GUI の GTK 設定を、`nixos/default.nix` / `darwin/default.nix` が各 OS の導入を管理する。`dotfiles.fonts.enable` に従う。基本フォントは NixOS / nix-darwin 統合ではシステム、standalone Home Manager では `home.packages` が導入する。`wsl-fontconfig.conf` は WSL の fontconfig asset を所有する。WSLg の配布と dconf service の登録は `nix/defaults.nix` の WSL 設定が担当する
- `1password/`: CLI / GUI の導入、account・SSH 公開鍵の既定値、SSH agent、署名、WSL interop を管理する。通常の CLI / GUI は Home Manager が所有し、OS 別の署名・agent・WSL 連携と移行処理は `nix/defaults.nix` に置く。署名スクリプトは同ディレクトリの `op-ssh-sign-wsl`
- `git/`: 共通 Git・ghq・gwq の導入と設定・alias。WSL の保存先・Git trust と OS 別の署名連携は `nix/defaults.nix`
- `desktop/default.nix` / `dock/default.nix` / `finder/default.nix`: macOS のデスクトップ設定と反映。Dock は導入する Nix package の `.app` を参照する
- Homebrew / nix-homebrew・Docker Desktop / Steam の cask・ユーザー PATH は `nix/defaults.nix` が管理する
- `aerospace/` / `hyprland/`: キー設定生成関数とユーザー設定。Hyprland のシステムセッションは `nix/defaults.nix` の Linux 設定
- `fcitx5/default.nix` / `gnome-keyring/` / `editors/vscode/default.nix` / `nvidia/nixos/default.nix`: 各アプリの設定・サービス・activation
- `ssh/default.nix`: SSH の共通 Home Manager 設定。1Password agent の接続設定は `1password/ssh/default.nix` が担当する
- `discord/`: Home Manager 標準 `programs.discord` の設定。Darwin / native Linux から読み込み、WSL には導入しない
- `lazygit/`: CLI の有効化と Bash / Zsh の `lg` 連携
- `superfile/`: WSL 用の標準 `programs.superfile` による導入、組み込みテーマ、Neovim とファイルプレビューの設定。選択は `nix/defaults.nix` が管理し、お気に入りなどの可変データはアプリが所有する
- `ai_agents/mcp/default.nix`: `programs.mcp.servers` に `MCP_DOCKER` / `chrome` / `xapi` / `pipedream` を定義する。Chrome / X API の client 接続先は `http://127.0.0.1:8765/mcp` / `http://127.0.0.1:8766/mcp`。Home Manager のユーザーサービス `mcp-chrome` / `mcp-xapi` が `pkgs.mcp-proxy` で各 stdio child を一つずつ常駐させ、Hermes root の `.browser` / `.xurl` を共有する。Linux は systemd、Darwin は launchd が管理する。browser は headless で起動する。Codex の標準 MCP integration と Hermes の型付き `services.hermes-agent.mcpServers` が同じ HTTP 定義を使う。Pipedream の OAuth は client ごとにユーザーが行う
- `ai_agents/mcp-packages.nix`: Chrome DevTools MCP は `inputs.mcp-servers`（`github:natsukium/mcp-servers-nix`）の既製 package を再利用する。xurl は `inputs.xurl` が取得する upstream `xdevplatform/xurl` の `main` の non-flake source を `buildGoModule` で構築し、version は source の revision から生成する。各 input は `flake.lock` で固定する
- `ai_agents/hermes/`: `default.nix` が公式 Home Manager module による導入、root 設定・Desktop・gateway と外部 LCM の `extraPlugins = [ inputs.hermes-lcm ]` を宣言する。named profile の設定と個別 secret refs は Git 正本に置き、公式 `hermes profile install` / `update` を使う。named profile は root の MCP 設定を継承しない
- `shells/plugins/`: bat / eza / fd / fzf / ripgrep / zoxide の導入・共通設定・シェル連携と zsh-patina の activate 連携。各アプリの module がそれぞれを所有する
- `shells/plugins/starship/`: CLI の有効化、Bash / Zsh の標準連携と `programs.starship.settings` のプロンプト設定を管理し、Home Manager が `starship.toml` を生成する
- `editors/nvim/`: Neovim の有効化・設定・プラグイン・Lua 配置と、`runtime/default.nix` による補助 CLI・LSP・整形ツール・toolchain・プラグイン実行依存の導入。追加ソースは `modes-nvim` / `devcontainer-cli-nvim` flake input で管理する
- `terminals/`: Ghostty / WezTerm の `default.nix` を自動検出し、構成側の `programs.ghostty.enable` / `programs.wezterm.enable` に従う。Ghostty の package / systemd の OS 差分もアプリ module が扱う
- `herdr/`: CLI の有効化と、標準 `programs.herdr.settings` によるキー設定
- `shells/zsh/default.nix`: zsh の有効化・`dotDir`・履歴・option・alias・キー設定・初期化・補完を管理する。`nix/defaults.nix` が選択し、標準 Home Manager が XDG 配下に `.zshrc` などを生成する
- `shells/bash/default.nix`: Bash の有効化・設定と共通 `home.sessionPath`。有効化は `nix/defaults.nix` の `programs.bash.enable`
- アプリ固有の system / Home Manager 設定・service・activation は各 module、OS 基盤設定と型付き option による有効化は `nix/defaults.nix`。CPU architecture は `system` 引数で選択する

## ルール

- enable・単純な package list・単一代入だけの module は作らず、必要な構成へ直接書く。

- すべての実 module は `default.nix` を入口にし、`nix/discover-modules.nix` で自動検出する。通常のアプリディレクトリは Home Manager、`nixos/` / `darwin/` / `system/` ディレクトリ配下は NixOS / nix-darwin / 両 OS 共通の scope とする。たとえば `fonts/default.nix`、`fonts/nixos/default.nix`、`fonts/darwin/default.nix`。アプリごとの import パス登録・公開一覧は作らない。構成側は標準 `programs.<name>.enable` などの型付き option を選び、設定・package・service・activation を enable に従わせる。標準 option がない機能だけ型付き option を定義する。純粋な factory・renderer は通常の関数として維持し、`default.nix` にしない。
- ユーザー環境の Python は Hermes 同梱の interpreter を使う。`nix/defaults.nix` で導入する uv はプロジェクト依存を管理し、Python interpreter を別途導入しない。Nix 内部専用の Python 依存はその module に置く。
- GitHub CLI の home / Darwin system package は `nix/defaults.nix` に宣言する。既存の `~/.config/gh/config.yml` はユーザーが管理する。
- 通常の CLI・GUI とユーザー設定は Home Manager、アプリ固有の OS 設定・サービスは対応する scope の module が管理し、OS 基盤設定と有効化は `nix/defaults.nix` の各 OS ブロックで選ぶ。アプリ導入の集約 module は作らず、自動検出された module は構成側の option で有効化する。OS service・フォント・ビルド用依存はそれぞれの所有先に置く。
- 設定・サービスから絶対 store path で呼び出す専用の実行依存は、その module が管理する。zsh-patina の activate 連携もこの範囲に含む。
- ここでは複数ホストで再利用できる単位に分割する。
- Windows の WinGet 導入情報は `windows/winget/packages.json` に直接定義し、Unix module に Windows install metadata を置かない。
