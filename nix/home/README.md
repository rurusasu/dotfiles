# Home Manager レイアウト

`nix/home/` はキー配列の補助定義と WSL の署名スクリプトを保持します。
Home Manager の設定と module の選択は `nix/default.nix` の `homeModules` に統合しています。

| 属性                 | 内容                                     |
| -------------------- | ---------------------------------------- |
| `homeModules.common` | 共通設定                                 |
| `homeModules.darwin` | macOS のユーザー設定                     |
| `homeModules.linux`  | native / standalone Linux のユーザー設定 |
| `homeModules.wsl`    | WSL のユーザー設定                       |

`homeModules.linux` は native NixOS と standalone Linux の双方から読み込み、ユーザー情報・GUI 選択・Git 署名を Home Manager の scope で設定します。

`homeModules.common` は `xdg.enable = true` と `home.preferXdgDirectories = true` を設定し、対応する標準 module の配置を XDG に揃えます。Unix の `CODEX_HOME` は `${config.xdg.configHome}/codex`（既定 `~/.config/codex`）です。ユーザーコマンドの PATH は `home.sessionPath` に宣言します。PATH には `~/.bun/bin`、`~/.local/bin`、`~/bin`、`~/.local/npm/bin` をこの順で全 Unix 環境へ追加します。

## import 方向

```text
flake.nix -> default.nix:configurations
            ├── hostModules.darwin -> homeModules.darwin -> homeModules.common
            ├── hostModules.linux  -> homeModules.linux  -> homeModules.common
            ├── hostModules.wsl    -> homeModules.wsl    -> homeModules.common
            └── standalone        -> homeModules.darwin | homeModules.linux
```

- caller は Darwin / WSL の `nix/default.nix:homeModules`、Linux の `nix/default.nix:homeModules.linux` を import する。
  共通・OS 別ユーザー設定は `nix/default.nix`、共通のフォント設定は `nix/modules/fonts/` が担当する。
  基本フォントは NixOS / nix-darwin 統合ではシステム側が導入し、standalone Home Manager では
  `home.packages` が導入する。Darwin standalone の配布先は標準の `$HOME/Library/Fonts/HomeManager`。
- 各 OS の Home Manager module は `nix/default.nix:homeModules.common` を import する。native NixOS / standalone Linux は CPU architecture にかかわらず `homeModules.linux` を共有する。
- Git は `../modules/git/` の `programs.git.settings` / `signing`、SSH は `../modules/ssh.nix` の `programs.ssh.settings` で生成する。`homeModules.common` が両方の module を読み込む。Git module 内の `ghq.nix` が共通保存先、`gwq.nix` が worktree の設定とシェル連携、`gtr.nix` が `gwq add` へ転送する既存 alias を管理する。
  Windows / WSL 共用のため worktree は相対リンクを使い、WSL の gwq 保存先を `/mnt/d/worktrees` に置く。Windows 設定と既存リンクの修復は [worktree の管理](../../docs/git/worktrees.md) を参照する。
  1Password の SSH agent socket は `../modules/1password/ssh.nix`、署名コマンドは `homeModules.darwin` / `homeModules.wsl` と `homeModules.linux`、WSL の署名スクリプトは `op-ssh-sign-wsl`、`ghq.root` は `homeModules.wsl` に置く。
  Git の実設定は `~/.config/git/config` に生成し、以前の `~/.gitconfig` はコメントだけの管理ファイルに置き換えて設定の二重読み込み・上書きを防ぐ。対象設定の移行にはバックアップを作らない。
- zsh の導入は `../modules/tools.nix`、履歴・alias・キー設定・補完・初期化は `../modules/shells/zsh/default.nix` にまとめる。`homeModules.common` がこの module を読み込み、Home Manager が XDG 配下に `.zshrc` などを生成する。
  kubectl / kind / helm / task の補完は Nix package が配布する `share/zsh/site-functions` を `fpath` から読み込み、起動時に各 CLI で生成しない。`compinit` は zsh-autocomplete が実行する。
  Kubernetes の alias は CLI の有無に関係なく定義するため、起動後に `nix shell` で追加したコマンドにも使える。一時的な `nix shell` だけで導入したツールの補完は、この初期化の保証対象に含めない。
- Bash の有効化は `../modules/tools.nix`、履歴・option・alias・追加初期化は `../modules/shells/bash/default.nix` の標準 `programs.bash` が担当し、`homeModules.common` から読み込む。Task の補完は package 付属の Bash completion を使う。
- `homeModules.common` は 1Password の個人用 account と SSH 公開鍵の既定値を宣言し、型付き option を持つ `../modules/1password/` を import する。`ssh.nix` が `IdentityAgent` と `SSH_AUTH_SOCK` を同じ公式 socket に設定し、公開鍵を `home.file` で `~/.ssh/signing_key.pub` に配布する。account と公開鍵は非秘密の値として Git / Nix store に含めてよい。CLI / GUI の導入は `../modules/tools.nix` が担当する。Git 署名は `homeModules.darwin` / `homeModules.wsl` と `homeModules.linux`、WSL interop は `homeModules.wsl` が担当し、WSL の `OP_ACCOUNT` は同じ account option を参照する。
- lazygit は `../modules/tools.nix` で有効化し、`../modules/lazygit/` が Bash / Zsh の `lg` 標準連携を設定する。
- Herdr は `../modules/tools.nix` で有効化し、`../modules/herdr/` で設定する。キー配列などを標準 `programs.herdr.settings` に Nix で直接定義し、Home Manager が設定ファイルを生成する。Windows は chezmoi 設定と既存の公式 installer を維持する。
- ChatGPT / Codex は `../modules/ai_agents/chatgpt/default.nix` が `packages`・`homeManager` を公開する。`../modules/tools.nix` が `packages` の返す `chatgpt` と `codex` を選び、Darwin と native / standalone Linux でアプリと同梱 CLI へのリンクを `home.packages` に指定する。`codex` は `pkgs.linkFarm` で同梱 CLI と `codex-code-mode-host`、Linux では `bwrap` も公開する。WSL では Linux 同梱 CLI へのリンクのみを選ぶ。`homeModules.common` が `homeManager` の Codex 設定を読み込み、`programs.codex` は `enable = true`・`package = null` で設定を管理する。WSL の GUI は導入せず、Windows 側は Windows アプリ付属 CLI を使う。
- Hermes Agent は `homeModules.common` が `../modules/ai_agents/hermes/default.nix` を読み込み、公式 Home Manager で root・Desktop・gateway を設定する。named profile は Git を正本とし、公式 `hermes profile install` / `update` で管理する。外部 LCM は `extraPlugins = [ inputs.hermes-lcm ]` に宣言する。操作は [Hermes](../../docs/hermes-agent/bootstrap.md) を参照。
- 共通 MCP は `homeModules.common` が読み込む `../modules/ai_agents/mcp.nix` の `programs.mcp.servers` に定義し、Codex の標準連携と root Hermes の型付き `services.hermes-agent.mcpServers` が取り込む。Chrome / X API は `http://127.0.0.1:8765/mcp` / `http://127.0.0.1:8766/mcp` に接続する。Home Manager のユーザーサービス `mcp-chrome` / `mcp-xapi` が `pkgs.mcp-proxy` で各 stdio child を一つずつ常駐させ、Hermes root の `.browser` / `.xurl` を共有する。Linux は systemd、Darwin は launchd が管理し、headless browser は WSLg / display を必要としない。`mcp-packages.nix` は Chrome DevTools MCP に `inputs.mcp-servers` の既製 package を使い、xurl は `inputs.xurl` の upstream `main` source を `buildGoModule` で構築する。xurl の version は source の revision から生成し、input は `flake.lock` で固定する。Google 連携のユーザー認証は [Pipedream](../../docs/hermes-agent/gmail-mcp.md) を参照。
- `homeModules.common` は `../modules/tools.nix` の `homeManager` を読み込む。GUI の導入も tools が宣言し、host が `linuxDesktop` / `wslDesktop` / `darwin` など対象の selector を import する。各アプリ module が固有設定・連携を担当し、shell の補助ツールは `../modules/shells/plugins/` にまとめる。
- zoxide のシェル標準連携は `../modules/shells/plugins/zoxide.nix` に置き、`--cmd cd` で `cd` / `cdi` を使う。WSL の除外ディレクトリは `homeModules.wsl` に置く。
- fzf の検索条件・プレビュー・Zsh 標準連携は `../modules/shells/plugins/fzf.nix` の `programs.fzf` と `fileWidget.zsh` / `changeDirWidget.zsh` option に定義する。
- eza の `programs.eza` 共通オプション・Zsh 標準連携と `ls` / `ll` / `la` / `lt` alias の差分は `../modules/shells/plugins/eza.nix` で定義する。
- bat のユーザー設定は `../modules/shells/plugins/bat.nix`、ripgrep の検索オプションは `../modules/shells/plugins/ripgrep.nix` で定義する。Unix の ripgrep 設定ファイルと `RIPGREP_CONFIG_PATH` は Home Manager が生成する。
- fzf / zoxide / eza / bat / ripgrep の Unix 導入は `../modules/tools.nix` が担当する。Windows の導入情報は `windows/winget/packages.json` を直接管理する。
- fd は `../modules/tools.nix` で導入し、fzf の `Alt+C` でディレクトリを列挙する。Starship は `../modules/tools.nix` で有効化し、`../modules/shells/plugins/starship/` が Bash / Zsh の標準連携と `programs.starship.settings` のプロンプト設定を管理し、Home Manager が `~/.config/starship.toml` を生成する。
- fd の `find` alias と fzf の検索コマンド・`_fzf_compgen_path` / `_fzf_compgen_dir` は `../modules/shells/plugins/fd.nix` で定義する。widget のコマンドは `programs.fzf.fileWidget.zsh.command` / `changeDirWidget.zsh.command`、通常検索は `FZF_DEFAULT_COMMAND`、補完は公式の `_fzf_compgen_*` hook を使う。通常の Zsh 補完はパッケージ付属のものを共有 Zsh 設定から読み込む。fzf の通常検索・`Ctrl+T` はファイル、`Alt+C` はディレクトリを検索し、内容検索は ripgrep の `rfg` が担当する。
- zsh-patina はシェル設定専用の実行依存として `../modules/shells/plugins/zsh-patina.nix` が絶対 store path を参照し、Zsh 初期化の最後に公式の `activate` を実行する。外部のプラグインマネージャーは使わない。
- `homeModules.wsl` は Patina の動的コマンド判定を無効にし、構文の色付けとファイル引数の下線を維持する。Windows PATH の同期探索を入力中に繰り返さないための設定で、native Linux / Darwin の判定は維持する。変更の反映後は共有 Patina daemon を一度再起動する。
- Starship の OS アイコンは `../modules/shells/plugins/starship/` が対象プラットフォームから選ぶ。Linux / WSL は `❄️`、macOS は `🍎` の静的な表示を生成し、プロンプトごとの OS 検出を省く。その他の OS は実行時検出を利用する。
- WSL の Git 状態は Windows drive 上では Windows の `starship.exe` に委譲し、Linux filesystem 上では Linux の処理を使う。Windows が Home Manager の絶対 symlink を辿れないため、WSL の `STARSHIP_CONFIG` は生成した store file の実体を直接参照する。Windows の導入情報と PATH の宣言は `windows/winget/packages.json` が所有する。WSL の自動補完は入力停止後 150ms・2文字以上から更新し、明示的な Tab 補完は既定の条件で利用する。
- Ghostty / WezTerm の `default.nix` は `homeModules.common` から一度だけ読み込む。Ghostty の package と systemd 連携は同 module が OS に応じて設定する。
- Neovim 本体・補助 CLI・LSP・プラグイン実行依存は `../modules/tools.nix` が導入する。`homeModules.common` が `../modules/editors/nvim` を読み込み、設定とプラグインを全 Unix 環境へ適用する。
- Orca は `../modules/tools.nix` が `inputs.llm-agents.packages.${system}.orca` を Home Manager に導入する。CLI は `orca`、GUI は `orca-ide`。Windows は引き続き WinGet が管理する。
- `homeModules.common` から OS 固有ファイルを import しない。
- Unix の設定は Codex を含め Home Manager が生成し、`files/` に展開済み dotfiles のコピーを置かない。chezmoi は Windows 専用。
- ユーザー環境の Python は Hermes 同梱の interpreter を使う。`../modules/tools.nix` の uv はプロジェクト依存の管理に使い、独立した interpreter を導入しない。
- `dsh` は `../modules/tools.nix` で upstream Nix package を導入する。Codex CLI は各 OS の ChatGPT アプリ付属のものを使う。Windows の npm/pnpm manifest は空で、dsh を導入しない。
- `nix/home/` 直下に `default.nix` と `users.nix` は作らない。入口と OS 依存方向を曖昧にするため。

standalone Home Manager のユーザー名は `rurusasu` を既定値とする。Darwin のホームディレクトリは
`homeModules.darwin` が実効ユーザー名から `/Users/<name>` を既定化し、明示指定で上書きできる。
Linux のホームディレクトリは `homeModules.linux`、WSL は `homeModules.wsl` が既定化する。nix-darwin / NixOS の
Home Manager submodule は OS のユーザー名・ホーム・Nix package を標準継承する。
共通の Lix・OS GC・Home Manager 接続は内部の `systemDefaults`、GC 日時は各 OS module、
standalone GC は `homeModules.common` が宣言する。
native NixOS のユーザー情報は`hostModules.nixos` 内の検出処理 が読み取る。
`../default.nix:hostModules.nixos` が native NixOS と WSL のアカウント・共通 system 設定・Docker・
Home Manager の system module import をまとめる。
共通の `system.stateVersion` は同ファイルで `26.05` に設定し、Home Manager の `home.stateVersion` は `homeModules.common` の `26.05` を使う。
WSL は公式 NixOS-WSL の `wsl.defaultUser` を使い、既定ユーザーを `nixos` とする。
ユーザー作成と UID の既定値は upstream module に任せ、Home Manager も同じユーザーを選ぶ。
ネイティブ NixOS では `SUDO_USER` と既存アカウントを使う。
Windows との JSON によるホスト情報の受け渡しは行わない。

## Home Manager 固有のチェック

`homeModules.darwin` は、システム GC と同じ日時に
ユーザー権限で `uv cache prune`、`go clean -cache`、Docker の build cache 整理を実行する。
Docker はローカルの Desktop socket に固定し、停止中は起動せずスキップする。
volume・container・image・Go module cache・Rust の project `target/` は削除しない。
Cargo の global cache は標準の自動 GC に任せる。Go の build cache は次回再生成される。
結果は `~/Library/Logs/tool-cache-maintenance.log` に記録する。

初回にこの agent だけを限定登録する場合は、生成した closure を
`~/.local/state/nix/gcroots/tool-cache-maintenance` で一時的に保護する。
正式な Home Manager activation 後、その generation の closure が agent の runner を
含むことを確認してから、この一時 GC root を解除する。限定登録で既存 generation は切り替えない。

- OS ごとのユーザー設定は Darwin / WSL が `nix/default.nix:homeModules`、native / standalone Linux が `nix/default.nix:homeModules.linux` に追加する。`homeModules.common` は OS 非依存の設定を担当する。
- Nix option、package、session variable のテストは `nix/tests/unit/` に追加し、
  全 system の flake 評価と対象 system の `nix-unit` build を実行する。
- Bats は Home Manager option の値を検査する用途には使わず、installer、shell、外部プロセス、
  runtime 契約に限る。Windows manifest は CI で JSON を直接検証する。分類は [Nix テスト](../tests/README.md) に記載する。

system 設定は `nix/default.nix:hostModules`、ユーザー設定は `homeModules`、公開構成は `configurations` が所有します。
Darwin の system font・loginwindow defaults・timezone・account・サービス・Homebrew・system activation は
`nix/default.nix:hostModules.darwin` に置きます。
Dock・Finder・trackpad などのユーザー defaults と反映 activation は `homeModules.darwin`、AeroSpace と
ユーザーキー設定は `keybindings/darwin.nix`、cache 整理は `homeModules.darwin` が管理します。
WSL のユーザー環境変数・VS Code server・`op` 連携は `homeModules.wsl`、署名スクリプトは `op-ssh-sign-wsl`、
fontconfig asset は `nix/modules/fonts/wsl-fontconfig.conf` が管理します。
