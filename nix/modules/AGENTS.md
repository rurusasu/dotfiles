# nix/modules: 再利用モジュール

## 管理対象

- `tools.nix`: Unix CLI / GUI の導入を管理する。CLI の `programs.*.enable` と `home.packages`、GUI の `linuxDesktop` / `wslDesktop` / `darwin` と既存の選択子をここに宣言する
- ComfyUI: `tools.nix` の `homeManager` が標準 `pkgs.comfyui` を Unix 共通で導入する。`comfyui` で起動し、Web UI は `http://127.0.0.1:8188` を使う
- `browsers/dia/default.nix`: `inputs.dia` を使う Darwin package 定義。導入は `tools.nix` の `darwin`
- `browsers/chrome/`: 標準 `programs.chromium` の固有設定と package factory。WSL の日本語 locale / fcitx 連携を管理する
- `shells/powershell/psscriptanalyzer.nix`: formatter 用 PSScriptAnalyzer の package 定義
- `ai_agents/chatgpt/`: `default.nix` が `packages`・`homeManager` を公開する。`packages` は共通 nixpkgs の `pkgs.chatgpt.override { codex = null; }` を使い、同梱 CLI と upstream の macOS 署名保持を利用する `chatgpt` と同梱 CLI へのリンクの `codex` を返す。`codex` は `pkgs.linkFarm` で `bin/codex`・`bin/codex-code-mode-host` と Linux の `bin/bwrap` を提供する。`tools.nix` が Darwin / native・standalone Linux のアプリと同梱 CLI へのリンクを `home.packages` で宣言する。WSL は同じ Linux 同梱 CLI へのリンクを選び、GUI アプリは直接配布しない。`common.nix` が `homeManager` を読み込み、標準 `programs.codex` は `enable = true`・`package = null` で config を管理する。`mutableSettings` でアプリの設定追記を保持し、公式 desktop worktree cleanup を宣言する。Windows の導入は `windows/winget/packages.json`、ユーザー設定は chezmoi が所有する
- `fonts.nix`: Darwin / NixOS 共通のフォントパッケージと fontconfig の既定フォント
- `fonts/`: `default.nix` が共通の Home Manager fontconfig と Linux GUI の GTK 設定を管理する。基本フォントは NixOS / nix-darwin 統合ではシステム、standalone Home Manager では `home.packages` が導入する。`japanese.nix` は WSL の日本語 fallback、`wsl-fontconfig.conf` は WSL の fontconfig asset を所有する。OS のフォント配布・dconf service の登録は `nix/hosts/*.nix` が担当する
- `1password/`: CLI / GUI の導入は `tools.nix`。`default.nix` が型付き Home Manager option の `dotfiles.onePassword.account` / `dotfiles.onePassword.ssh.publicKey` を定義して SSH 設定を読み込む。個人用の既定値は `nix/home/1password.nix` に一度だけ宣言する。`ssh.nix` が公開鍵 option を参照し、公式 agent socket の `IdentityAgent` / `SSH_AUTH_SOCK` と `home.file` による `~/.ssh/signing_key.pub` の宣言管理を担当する。account と公開鍵は非秘密の値として Git / Nix store に含めてよい。Git signer は Darwin / WSL の `nix/home/{darwin,wsl}.nix` と Linux の `nix/hosts/default.nix` の `linuxHome`、Windows の `op.exe` を使う WSL interop は `nix/home/wsl.nix`、WSL 署名スクリプトは `nix/home/op-ssh-sign-wsl` に置く
- `git/`: Git 共通設定と相対 worktree リンクを `default.nix`、ghq の共通保存先を `ghq.nix`、gwq 設定とシェル連携を `gwq.nix`、`gwq add` へ転送する既存 alias を `gtr.nix` にまとめる。Git / ghq / gwq の導入は `tools.nix`、署名コマンドは Darwin / WSL の `nix/home/{darwin,wsl}.nix` と Linux の `nix/hosts/default.nix` の `linuxHome`、WSL の保存先は `nix/home/wsl.nix` が担当する
- `ssh.nix`: SSH の共通 Home Manager 設定。1Password agent の接続設定は `1password/ssh.nix` が担当する
- `discord/`: Home Manager 標準 `programs.discord` の設定。Darwin / native Linux から読み込み、WSL には導入しない
- `lazygit/`: Bash / Zsh の `lg` 連携。CLI の有効化は `tools.nix` が担当する
- `ai_agents/mcp.nix`: `programs.mcp.servers` に `MCP_DOCKER` / `chrome` / `xapi` / `pipedream` を定義する。Chrome / X API の client 接続先は `http://127.0.0.1:8765/mcp` / `http://127.0.0.1:8766/mcp`。Home Manager のユーザーサービス `mcp-chrome` / `mcp-xapi` が `pkgs.mcp-proxy` で各 stdio child を一つずつ常駐させ、Hermes root の `.browser` / `.xurl` を共有する。Linux は systemd、Darwin は launchd が管理する。browser は headless で起動する。Codex の標準 MCP integration と Hermes の型付き `services.hermes-agent.mcpServers` が同じ HTTP 定義を使う。Pipedream の OAuth は client ごとにユーザーが行う
- `ai_agents/mcp-packages.nix`: Chrome DevTools MCP は `inputs.mcp-servers`（`github:natsukium/mcp-servers-nix`）の既製 package を再利用する。xurl は `inputs.xurl` が取得する upstream `xdevplatform/xurl` の `main` の non-flake source を `buildGoModule` で構築し、version は source の revision から生成する。各 input は `flake.lock` で固定する
- `ai_agents/hermes/`: `default.nix` が公式 Home Manager module の root 設定・Desktop・gateway と外部 LCM の `extraPlugins = [ inputs.hermes-lcm ]` を宣言する。named profile の設定と個別 secret refs は Git 正本に置き、公式 `hermes profile install` / `update` を使う。named profile は root の MCP 設定を継承しない
- `shells/plugins/`: bat / eza / fd / fzf / ripgrep / zoxide の共通設定・シェル連携と zsh-patina の activate 連携。CLI の導入は `tools.nix` が担当する
- `shells/plugins/starship/`: Bash / Zsh の標準連携と `programs.starship.settings` のプロンプト設定を管理する。CLI の有効化は `tools.nix` が担当し、Home Manager が `starship.toml` を生成する
- `editors/nvim/`: Neovim の設定・プラグイン・Lua 配置。追加ソースは `modes-nvim` / `devcontainer-cli-nvim` flake input で管理する。Neovim 本体と補助 CLI・LSP・プラグイン実行依存の導入は `tools.nix` が担当する
- Orca: `tools.nix` が `inputs.llm-agents.packages.${system}.orca` を導入する。CLI は `orca`、GUI は `orca-ide`
- `terminals/`: Ghostty / WezTerm の Home Manager 設定。`nix/home/common.nix` が各 `default.nix` を一度だけ読み込み、Ghostty の package / systemd の OS 差分も `default.nix` が扱う
- `herdr/`: 標準 `programs.herdr.settings` にキー設定を Nix で直接定義する。CLI の有効化は `tools.nix` が担当する
- `shells/zsh/default.nix`: zsh の `dotDir`・履歴・option・alias・キー設定・初期化・補完を Nix に集約する。`common.nix` が読み込み、標準 Home Manager が XDG 配下に `.zshrc` などを生成する。CLI の有効化は `tools.nix`
- `shells/bash/default.nix`: Bash の履歴・option・alias・追加初期化を標準 `programs.bash` にまとめる。CLI の有効化は `tools.nix` が担当し、`nix/home/common.nix` から読み込む。共通 PATH は `common.nix` の `home.sessionPath` が所有する
- OS の system option・service・system module の配線は `nix/hosts/*.nix`、Home Manager の OS 別設定は Darwin / WSL の `nix/home/{darwin,wsl}.nix` と native / standalone Linux 共通の `nix/hosts/default.nix` の `linuxHome` が担当する。CPU architecture は `system` 引数で選択する

## ルール

- OS の system 動作は `nix/hosts/*.nix`、共通・Darwin・WSL のユーザー設定・ユーザーサービスは `nix/home/`、Linux 共通の Home Manager module は `nix/hosts/default.nix` の `linuxHome` に置く。
- Python のユーザー環境は `tools.nix` が導入する uv で管理する。Python interpreter の直接導入は行わず、Nix 内部専用の Python 依存はその module に置く。
- GitHub CLI は `tools.nix` の `home.packages` に `gh` を導入し、Darwin の host 連携用 system package も `tools.nix` の `darwin` に残す。既存の `~/.config/gh/config.yml` はユーザーが管理する。
- CLI / GUI の導入は `tools.nix`、固有設定・連携・package 定義は各アプリ module に置く。host が tools の対象 OS selector を import して構成を選ぶ。OS service・フォント・ビルド用依存はそれぞれの所有先に置く。
- 設定・サービスから絶対 store path で呼び出す専用の実行依存は、その module が管理する。zsh-patina の activate 連携もこの範囲に含む。
- ここでは複数ホストで再利用できる単位に分割する。
- Windows の WinGet 導入情報は `windows/winget/packages.json` に直接定義し、Unix module に Windows install metadata を置かない。
