# Home Manager レイアウト

`nix/home/` は OS 非依存の Home Manager ユーザー設定です。OS 固有設定と module の選択は `nix/hosts/` に置きます。Darwin は `aarch64-darwin/home.nix`、WSL は `x86_64-linux/wsl/home.nix`、Linux 共通設定は `shared/linux-home.nix` が所有します。

| 入口                            | 内容                                      |
| ------------------------------- | ----------------------------------------- |
| `common.nix`                    | 共通設定                                  |
| `shells/zsh/`                   | zsh の履歴・alias・キー設定               |
| `shells/plugins/zoxide.nix`     | zoxide の Bash / Zsh 標準連携             |
| `shells/plugins/bat.nix`        | bat のユーザー設定（現在は既定値）        |
| `shells/plugins/ripgrep.nix`    | ripgrep の検索オプション                  |
| `shells/plugins/eza.nix`        | eza の共通オプション・Zsh 標準連携        |
| `shells/plugins/fd.nix`         | fd の Zsh alias・パッケージ付属の補完     |
| `shells/plugins/fzf.nix`        | fzf の検索条件・プレビューと Zsh 標準連携 |
| `shells/plugins/zsh-patina.nix` | zsh-patina の公式 activate 連携           |

## import 方向

```text
flake.nix -> hosts/configurations.nix -> hosts/<system>/ -> home/common.nix
```

- caller は対象 host の `home.nix` を import する。
  Darwin のユーザー・フォント設定は `nix/hosts/aarch64-darwin/home.nix` に集約する。standalone ではフォントを
  `home.packages` に追加し、Home Manager 標準機能で `$HOME/Library/Fonts/HomeManager` に配布する。
  nix-darwin 統合ではシステム側がフォントを導入し、Home Manager は fontconfig 設定を担当する。
- 各環境の設定は `nix/home/common.nix` を import する。Linux の各 system の `home.nix` は `hosts/shared/linux-home.nix` を読み込むだけにする。
- Git は `../modules/git/` の `programs.git.settings` / `signing`、SSH は `../modules/ssh.nix` の `programs.ssh.settings` で生成する。`common.nix` が両方の module を読み込む。Git module 内の `ghq.nix` が共通保存先、`gtr.nix` が既存の `git gtr` alias を管理する。
  1Password の SSH agent socket は `../modules/1password/ssh.nix`、署名コマンドと WSL の署名 wrapper・`ghq.root` は各 host の `home.nix` に置く。
  Git の実設定は `~/.config/git/config` に生成し、以前の `~/.gitconfig` はコメントだけの管理ファイルに置き換えて設定の二重読み込み・上書きを防ぐ。対象設定の移行にはバックアップを作らない。
- zsh の導入は `../modules/tools.nix`、補完プラグインは `../modules/shells/zsh/` が担当する。`common.nix` は `./shells/zsh/` からユーザー設定を読み込む。
- Bash の有効化は `../modules/tools.nix`、初期化・ログイン設定は `../modules/shells/bash/` が担当し、`common.nix` から読み込む。
- 1Password の CLI / GUI は `../modules/tools.nix`、SSH agent 設定は `../modules/1password/` が担当する。Linux の GUI は Home Manager、macOS の GUI は nix-darwin に導入する。`ssh.nix` が `IdentityAgent` と `SSH_AUTH_SOCK` を同じ公式 socket に設定する。Bash は別の `ssh-agent` を起動しない。Git 署名・WSL interop の設定は各 host に残す。
- lazygit は `../modules/tools.nix` で有効化し、`../modules/lazygit/` が Bash / Zsh の `lg` 標準連携を設定する。
- Herdr は `../modules/tools.nix` で有効化し、`../modules/herdr/` で設定する。キー配列などを標準 `programs.herdr.settings` に Nix で直接定義し、Home Manager が設定ファイルを生成する。Windows は chezmoi 設定と既存の公式 installer を維持する。
- ChatGPT は `../modules/tools.nix` が macOS のアプリを導入し、`common.nix` が `../modules/ai_agents/chatgpt/` を読み込む。同梱 Codex の設定も同じ module で管理し、Codex CLI は独立導入しない。
- Hermes Agent の CLI は `../modules/tools.nix` で有効化する。`common.nix` が `../modules/ai_agents/hermes/` を読み込み、gateway・CLI 設定・bootstrap manifest を管理する。`bootstrap.nix` が bootstrap の構築を担当する。既存の `~/.hermes`、依存 pin、macOS の launchd / Linux の systemd-user 設定は維持する。
- `common.nix` は `../modules/tools.nix` の `homeManager` を読み込み、Unix CLI / GUI を有効化・導入する。各アプリ module と `./shells/plugins/` が設定・連携を担当する。
- zoxide のシェル標準連携は `./shells/plugins/zoxide.nix` に置き、`--cmd cd` で `cd` / `cdi` を使う。WSL の除外ディレクトリは `nix/hosts/x86_64-linux/wsl/home.nix` に置く。
- fzf の検索条件・プレビュー・Zsh 標準連携は `./shells/plugins/fzf.nix` で読み込む。
- eza の `programs.eza` 共通オプション・Zsh 標準連携と `ls` / `ll` / `la` / `lt` alias の差分は `./shells/plugins/eza.nix` で定義する。
- bat のユーザー設定は `./shells/plugins/bat.nix`、ripgrep の検索オプションは `./shells/plugins/ripgrep.nix` で定義する。Unix の ripgrep 設定ファイルと `RIPGREP_CONFIG_PATH` は Home Manager が生成する。
- fzf / zoxide / eza / bat / ripgrep の Unix 導入は `../modules/tools.nix` が担当する。Windows の導入情報は `windows/winget/packages.json` を直接管理する。
- fd は `../modules/tools.nix` で導入し、fzf の `Alt+C` でディレクトリを列挙する。Starship は `../modules/tools.nix` で有効化し、`../modules/shells/plugins/starship/` が Zsh 標準連携と `programs.starship.settings` のプロンプト設定を管理し、Home Manager が `~/.config/starship.toml` を生成する。
- fd の `find` alias と fzf の検索コマンド・`_fzf_compgen_path` / `_fzf_compgen_dir` は `./shells/plugins/fd.nix` で定義する。通常の Zsh 補完はパッケージ付属のものを共有 Zsh 設定から読み込む。fzf の通常検索・`Ctrl+T` はファイル、`Alt+C` はディレクトリを検索し、内容検索は ripgrep の `rfg` が担当する。
- zsh-patina はシェル設定専用の実行依存として `./shells/plugins/zsh-patina.nix` が絶対 store path を参照し、Zsh 初期化の最後に公式の `activate` を実行する。外部のプラグインマネージャーは使わない。
- Neovim 本体・補助 CLI・LSP・プラグイン実行依存は `../modules/tools.nix` が導入する。Darwin / WSL の `home.nix` と `hosts/shared/linux-home.nix` は `nix/modules/editors/nvim` を import し、設定とプラグインを適用する。
- Orca は `../modules/tools.nix` が `../modules/editors/orca/package.nix` を選択し、Home Manager の `home.packages` で導入する。macOS は公式 DMG、Linux（x86_64 / ARM64）は公式 AppImage を使用する。Linux の CLI は公式と同じ `orca-ide`、macOS は `orca`。Windows は引き続き WinGet が管理する。
- `common.nix` から OS 固有ファイルを import しない。
- Unix の設定は Codex を含め Home Manager が生成し、`files/` に展開済み dotfiles のコピーを置かない。chezmoi は Windows 専用。
- Python のユーザー環境は `../modules/tools.nix` が導入する uv で管理し、interpreter を直接 `home.packages` に追加しない。公開 Python コマンドは uv 経由で実行する。
- Node.js/npm と `dsh` は `../modules/tools.nix` で導入し、dsh は upstream Nix package を使用する。pnpm と Bun は導入せず、Codex CLI は ChatGPT アプリ付属のものを使う。Windows の npm/pnpm manifest は空で、dsh を導入しない。
- `nix/home/` 直下に `default.nix` と `users.nix` は作らない。入口と OS 依存方向を曖昧にするため。

standalone Home Manager のユーザー名は `rurusasu` を既定値とする。Darwin のホームディレクトリは
`nix/hosts/aarch64-darwin/home.nix` が実効ユーザー名から `/Users/<name>` を既定化し、明示指定で上書きできる。
Linux / WSL のホームディレクトリは各 OS ファイルが既定化する。nix-darwin / NixOS の
Home Manager submodule は host の `users.users.<name>.home` を使う。
NixOS のユーザー情報は `hosts/shared/nixos/identity.nix` が読み取る。
Windows の初回セットアップは `/etc/nixos/dotfiles.json` に選択したユーザー・ホーム・checkout・
stateVersion を保存する。通常の rebuild は `sudo nixos-rebuild` を直接実行し、
Nix が同じホスト情報を読み取る。ネイティブ NixOS では `SUDO_USER` と既存アカウントを使う。

## Home Manager 固有のチェック

Darwin の `hosts/aarch64-darwin/cache-maintenance.nix` は、システム GC と同じ日時に
ユーザー権限で `uv cache prune`、`go clean -cache`、Docker の build cache 整理を実行する。
Docker はローカルの Desktop socket に固定し、停止中は起動せずスキップする。
volume・container・image・Go module cache・Rust の project `target/` は削除しない。
Cargo の global cache は標準の自動 GC に任せる。Go の build cache は次回再生成される。
結果は `~/Library/Logs/tool-cache-maintenance.log` に記録する。

初回にこの agent だけを限定登録する場合は、生成した closure を
`~/.local/state/nix/gcroots/tool-cache-maintenance` で一時的に保護する。
正式な Home Manager activation 後、その generation の closure が agent の runner を
含むことを確認してから、この一時 GC root を解除する。限定登録で既存 generation は切り替えない。

- OS 固有設定は `nix/hosts/<system>/<environment>/home.nix` に追加し、`nix/home/` に OS 条件を増やさない。
- Nix option、package、session variable のテストは `nix/tests/unit/` に追加し、
  全 system の flake 評価と対象 system の `nix-unit` build を実行する。
- Bats は Home Manager option の値を検査する用途には使わず、installer、shell、外部プロセス、
  runtime 契約に限る。Windows manifest は CI で JSON を直接検証する。分類は [Nix テスト](../tests/README.md) に記載する。

ホストの system 設定は `nix/hosts/<system>/<environment>/configuration.nix` と責務別 host module、import の入口は
同じディレクトリの `default.nix` が所有します。Darwin の system font は `nix/hosts/aarch64-darwin/`、OS-wide
defaults、timezone、defaults の反映 activation は `system.nix`、host identity、サービス、Homebrew、
統合固有の activation は `configuration.nix` に置きます。共有する Home Manager の OS 差分は
`nix/hosts/<system>/<environment>/home.nix`、standalone 専用の責務は caller が組み合わせる個別 module に置きます。
