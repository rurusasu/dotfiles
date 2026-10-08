# Home Manager レイアウト

`nix/home/` は OS 非依存の Home Manager ユーザー設定です。OS 固有設定とパッケージ選択は `nix/hosts/` に置きます。Darwin は `aarch64-darwin/home.nix`、WSL は `x86_64-linux/wsl/home.nix`、Linux 共通設定は `shared/linux-home.nix` が所有します。

| 入口                            | 内容                                                 |
| ------------------------------- | ---------------------------------------------------- |
| `common.nix`                    | 共通設定                                             |
| `pnpm.nix`                      | pnpm の保存先（標準 module が環境変数・PATH を生成） |
| `shells/zsh/`                   | zsh の履歴・alias・キー設定                          |
| `shells/plugins/zoxide.nix`     | zoxide の Bash / Zsh 標準連携                        |
| `shells/plugins/bat.nix`        | bat のユーザー設定（現在は既定値）                   |
| `shells/plugins/ripgrep.nix`    | ripgrep の検索オプション                             |
| `shells/plugins/eza.nix`        | eza の共通オプション・Zsh 標準連携                   |
| `shells/plugins/fd.nix`         | fd の Zsh alias・パッケージ付属の補完                |
| `shells/plugins/fzf.nix`        | fzf の検索条件・プレビューと Zsh 標準連携            |
| `shells/plugins/zsh-patina.nix` | zsh-patina の公式 activate 連携                      |

## import 方向

```text
flake.nix -> hosts/configurations.nix -> hosts/<system>/ -> home/common.nix
```

- caller は対象 host の `home.nix` を import する。
  Darwin のユーザー・フォント設定は `nix/hosts/aarch64-darwin/home.nix` に集約する。standalone ではフォントを
  `home.packages` に追加し、Home Manager 標準機能で `$HOME/Library/Fonts/HomeManager` に配布する。
  nix-darwin 統合ではシステム側がフォントを導入し、Home Manager は fontconfig 設定を担当する。
- 各環境の設定は `nix/home/common.nix` を import する。Linux の各 system の `home.nix` は `hosts/shared/linux-home.nix` を読み込むだけにする。
- Git は `../modules/git/` の `programs.git.settings` / `signing`、SSH は `../modules/ssh.nix` の `programs.ssh.settings` で生成する。`common.nix` が両方の module を読み込む。Git module 内の `ghq.nix` が ghq と共通保存先、`gtr.nix` が既存の `git gtr` alias、`windows-install.nix` が Git / ghq の Windows 配布・検証情報を管理する。
  1Password の SSH agent socket は `../modules/1password/ssh.nix`、署名コマンドと WSL の署名 wrapper・`ghq.root` は各 host の `home.nix` に置く。
  Git の実設定は `~/.config/git/config` に生成し、以前の `~/.gitconfig` はコメントだけの管理ファイルに置き換えて設定の二重読み込み・上書きを防ぐ。対象設定の移行にはバックアップを作らない。
- zsh の導入・補完プラグインは `../modules/shells/zsh/` が担当する。`common.nix` は `./shells/zsh/` からユーザー設定を読み込む。
- Bash の有効化・初期化・ログイン設定は `../modules/shells/bash/` が担当し、`common.nix` から読み込む。
- 1Password の導入と Windows 配布・検証 metadata は `../modules/1password/` にまとめる。`common.nix` が CLI と Linux デスクトップ版を導入する Home Manager module を読み込み、macOS デスクトップ版は Darwin host が同じ module の `darwin-system.nix` からシステムに導入する。`ssh.nix` が `IdentityAgent` と `SSH_AUTH_SOCK` を同じ公式 socket に設定する。Bash は別の `ssh-agent` を起動しない。Git 署名・WSL interop の設定は各 host に残す。
- lazygit は `../modules/lazygit/` の標準 `programs.lazygit` で導入し、Bash / Zsh の `lg` は標準 wrapper を使う。Windows の配布・検証 metadata も同じ module の `windows-install.nix` に置く。
- Herdr は `../modules/herdr/` の標準 `programs.herdr` で導入・設定する。キー配列などの既存 TOML を同じ module の `config.toml` にまとめ、標準 `settings` に読み込ませて Home Manager が設定ファイルを生成する。Windows は chezmoi 設定と既存の公式 installer を維持する。
- Hermes Agent は `common.nix` が `../modules/hermes-agent/` を読み込み、公式 Home Manager module の CLI / gateway と既存 bootstrap を有効化する。bootstrap manifest も同じ module 内で管理する。既存の `~/.hermes`、依存 pin、macOS の launchd / Linux の systemd-user 設定は維持する。
- `common.nix` は `../modules/shells/plugins/` の fzf / zoxide / eza / bat / ripgrep を有効化する。
- zoxide のシェル標準連携は `./shells/plugins/zoxide.nix` に置き、`--cmd cd` で `cd` / `cdi` を使う。WSL の除外ディレクトリは `nix/hosts/x86_64-linux/wsl/home.nix` に置く。
- fzf の検索条件・プレビュー・Zsh 標準連携は `./shells/plugins/fzf.nix` で読み込む。
- eza の `programs.eza` 共通オプション・Zsh 標準連携と `ls` / `ll` / `la` / `lt` alias の差分は `./shells/plugins/eza.nix` で定義する。
- bat のユーザー設定は `./shells/plugins/bat.nix`、ripgrep の検索オプションは `./shells/plugins/ripgrep.nix` で定義する。Unix の ripgrep 設定ファイルと `RIPGREP_CONFIG_PATH` は Home Manager が生成する。
- 5 ツールの Unix 導入は各 program module が担当し、パッケージカタログには置かない。Windows の配布情報は `nix/packages/install/` で管理する。
- fd と Starship は既存のパッケージカタログで導入する。fd は fzf の `Alt+C` でディレクトリを列挙し、Starship は Home Manager の Zsh 標準連携を使う。
- fd の `find` alias と fzf の検索コマンド・`_fzf_compgen_path` / `_fzf_compgen_dir` は `./shells/plugins/fd.nix` で定義する。通常の Zsh 補完はパッケージ付属のものを共有 Zsh 設定から読み込む。fzf の通常検索・`Ctrl+T` はファイル、`Alt+C` はディレクトリを検索し、内容検索は ripgrep の `rfg` が担当する。
- zsh-patina はパッケージカタログで導入し、`./shells/plugins/zsh-patina.nix` で Zsh 初期化の最後に公式の `activate` を実行する。外部のプラグインマネージャーは使わない。
- Neovim は Darwin / WSL の `home.nix` と `hosts/shared/linux-home.nix` が `nix/modules/editors/nvim` を直接 import する。
- Orca は `common.nix` が `../modules/editors/orca` を読み込み、Home Manager の `home.packages` で導入する。macOS は公式 DMG、Linux（x86_64 / ARM64）は公式 AppImage を使用する。Linux の CLI は公式と同じ `orca-ide`、macOS は `orca`。Windows は引き続き WinGet が管理する。
- `common.nix` から OS 固有ファイルを import しない。
- Unix の設定は Home Manager が生成し、`files/` に展開済み dotfiles のコピーを置かない。例外の `.codex/` / `.claude/` は chezmoi が直接配布する。
- pnpm の導入は `../modules/pnpm.nix`、保存先は `pnpm.nix` の標準 `programs.pnpm` option で管理する。`PNPM_HOME` と PATH は Home Manager に生成させ、カタログからの重複導入やグローバルパッケージ導入 activation は持たない。`dsh` は `../modules/dsh.nix` から Numtide の既存 flake を参照する。Windows の pnpm グローバルパッケージも `dsh` のみとし、配布情報は `nix/packages/install/node.nix` に残す。
- `nix/home/` 直下に `default.nix` と `users.nix` は作らない。入口と OS 依存方向を曖昧にするため。

standalone Home Manager のユーザー名は `rurusasu` を既定値とする。Darwin のホームディレクトリは
`nix/hosts/aarch64-darwin/home.nix` が実効ユーザー名から `/Users/<name>` を既定化し、明示指定で上書きできる。
Linux / WSL のホームディレクトリは各 OS ファイルが既定化する。nix-darwin / NixOS の
Home Manager submodule は host の `users.users.<name>.home` を使う。
NixOS は `DOTFILES_USER` 未指定時に `nixos` を使う。WSL postinstall は `--user` で選択した
ユーザーの `DOTFILES_USER` / `DOTFILES_HOME` / `DOTFILES_UID` / `DOTFILES_GID` /
`DOTFILES_GROUP` を export し、`nixos-rebuild` を `--impure` 付きで実行する。これにより
flake 評価中の `builtins.getEnv` が選択した識別情報を読み取り、NixOS host、Home Manager、
`wsl.defaultUser` の対象を一致させる。
`nrs` / `nrt` / `nrb` は `scripts/sh/nixos-rebuild-with-user.sh` 経由で実行し、同じ識別情報を
flake 評価へ渡す。

## Home Manager 固有のチェック

- OS 固有設定は `nix/hosts/<system>/<environment>/home.nix` に追加し、`nix/home/` に OS 条件を増やさない。
- Nix option、package、session variable のテストは `nix/tests/unit/` に追加し、
  全 system の flake 評価と対象 system の `nix-unit` build を実行する。
- Bats は Home Manager option の値を検査する用途には使わず、installer、shell、外部プロセス、
  runtime 契約に限る。`tests/bash/package_catalog.bats` の値テストは移管済みで、
  残る runtime / artifact 契約の分類は [Nix テスト](../tests/README.md) に記載する。
  `nixos_wsl_postinstall.bats` の `nix eval` は、stubbed `nixos-rebuild` 境界内で選択 user と
  `--impure` 伝播を実 Nix eval で確認する runtime/integration assertion に限る。新しい例外は追加しない。

ホストの system 設定は `nix/hosts/<system>/<environment>/configuration.nix` と責務別 host module、import の入口は
同じディレクトリの `default.nix` が所有します。Darwin の system font は `nix/hosts/aarch64-darwin/`、OS-wide
defaults、timezone、defaults の反映 activation は `system.nix`、host identity、サービス、Homebrew、
統合固有の activation は `configuration.nix` に置きます。共有する Home Manager の OS 差分は
`nix/hosts/<system>/<environment>/home.nix`、standalone 専用の責務は caller が組み合わせる個別 module に置きます。
