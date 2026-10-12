# パッケージ管理

## 管理方針

Unix CLI の PATH への導入はすべて `nix/modules/tools.nix` にまとめます。Home Manager 標準の `programs.*.enable` と、設定をユーザーが管理する CLI・標準 module のない CLI・LSP・プラグイン実行依存の `home.packages` をここに宣言します。各アプリ module は設定・連携・package override を担当し、`nix/home/common.nix` が tools と設定 module を並列に import します。

Python のユーザー環境は `uv` で管理し、`tools.nix` は uv を導入します。Python interpreter は直接 `home.packages` に追加しません。Darwin の package updater と X API 同期の公開コマンドは `uv run --no-project --managed-python --python 3.14 python ...` を使います。Hermes bootstrap など、Nix の構築・実行に閉じた専用 Python 依存は各 module が管理します。

GUI、OS service、フォント、ビルド用依存はそれぞれの module / host で管理します。設定・サービスから絶対 store path で呼び出す専用の実行依存は、その設定・サービスの module に宣言します。host は必要な module を import して構成を選択します。

Windows の導入情報は `windows/winget/packages.json` を直接管理します。Unix の Nix module と独立した正本で、Nix から生成しません。通常の Windows セットアップは GUI アプリだけを導入し、`windows/npm/packages.json` と `windows/pnpm/packages.json` は空です。

フォントパッケージと fontconfig 設定は `nix/modules/fonts.nix` の `fonts.packages` / `fonts.fontconfig` に一度だけ定義します。Darwin / NixOS のシステム構成はそれぞれ `nix/hosts/aarch64-darwin/platform.nix` / `nix/hosts/shared/nixos/platform.nix` を読み込み、OS 固有の option と配線はこの入口に記載します。NixOS は共通 module を import し、NixOS 専用の `fonts.fontDir.enable` を設定します。Darwin は `fonts.packages` を nix-darwin に渡し、`nix/hosts/aarch64-darwin/home.nix` が `fonts.fontconfig` を設定します。Linux / WSL と standalone Darwin の Home Manager は各 entrypoint から共通定義を直接参照します。standalone Darwin のフォント配布は Home Manager 標準機能を使います。

共通の `fonts.fontconfig.defaultFonts` は `monospace` / `sansSerif` / `serif` を `UDEV Gothic NF`、`emoji` を `Noto Color Emoji` に設定します。Darwin での既定フォント設定は fontconfig を使うアプリに適用され、macOS 標準 UI / CoreText の既定フォントは変更しません。

## 分割の理由と編集先

Unix CLI の導入は `tools.nix`、設定・連携はアプリ・機能ごとの module にまとめます。Windows の manifest、OS の service、有効化、ユーザー設定は、それぞれを適用する層が管理します。

| 編集先                                               | 責務                                                                                        |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `nix/modules/tools.nix`                              | 全 Unix CLI の `programs.*.enable`、その他の CLI・LSP・プラグイン実行依存の `home.packages` |
| `nix/modules/desktop.nix`                            | Linux / WSLg 共通の Chrome / Obsidian                                                       |
| `nix/modules/desktop-system.nix`                     | Darwin の system GUI                                                                        |
| `nix/modules/<app>/`                                 | CLI の設定・連携・package override、GUI の導入、custom package 定義                         |
| `nix/modules/ai_agents/hermes/bootstrap.nix`         | Hermes bootstrap の package 構築。CLI の導入は tools、サービス用依存は Hermes module        |
| `nix/modules/browsers/dia/`                          | Dia の package 選択関数、`package.nix`、更新用 `provider-candidates.nix`                    |
| `nix/modules/shells/powershell/psscriptanalyzer.nix` | formatter が使用する PSScriptAnalyzer の package 定義                                       |
| `nix/hosts/`                                         | module の選択、OS の service / 有効化・競合解除                                             |
| `nix/home/`                                          | OS 非依存の Home Manager 共通設定と module の読み込み                                       |
| `nix/home/keybindings/`                              | 共通キー配置・設定生成関数・ユーザー設定                                                    |
| `windows/winget/packages.json`                       | Windows GUI の package ID、導入・検証情報                                                   |
| `windows/{npm,pnpm}/packages.json`                   | 独立した Node package manifest。現在は空                                                    |
| `nix/outputs.nix`                                    | Windows キー設定の export と Darwin custom package の build 出力                            |

各 host の `home.nix` は `nix/home/common.nix` を通じて CLI 導入とアプリ設定を読み込みます。Darwin の system module は `desktop-system.nix` から GUI の system package を導入し、Homebrew は host が設定します。`desktop.nix` は Linux / WSLg の共通 GUI を導入します。native NixOS の Hyprland / Firefox / fuzzel / Nautilus は native host と `nix/home/keybindings/hyprland.nix` が所有し、WSL / standalone へ compositor を自動導入しません。Discord も Darwin / native Linux の Home Manager module から導入し、WSL では Windows のアプリを利用します。

[共通のキー割り当て](../chezmoi/omarchy.md) は `nix/home/keybindings/` に一度だけ定義し、host が OS 統合と有効化を担当します。共通データや純粋な設定生成関数は Home Manager module ではないため、`imports` に渡しません。

## パッケージの追加

CLI はすべて `nix/modules/tools.nix` に追加します。Home Manager で設定・連携も管理する CLI は標準の `programs.<name>.enable` を使います。設定をユーザーが管理する CLI と標準 module のない CLI は `home.packages` に宣言します。設定・連携・package override は対応する `nix/modules/<app>/` に置きます。GitHub CLI の `gh` は `home.packages` に導入し、既存の `~/.config/gh/config.yml` はユーザーが管理します。

```nix
# nix/modules/tools.nix の宣言例
{ pkgs, ... }:
{
  programs.starship.enable = true;
  home.packages = [ pkgs.mypackage ];
}
```

Linux / WSLg の共通 GUI は `desktop.nix`、Darwin の system GUI は `desktop-system.nix` に追加します。Homebrew と OS service は host module に定義します。Windows に追加する場合は `windows/winget/packages.json` を直接編集し、導入・検証情報を同じ entry に記述します。

## OS ごとの反映

通常は個別コマンドではなく one-command installer を再実行します。

```text
Windows:          install.cmd
macOS:            ./install.sh
NixOS:            ./install.sh
Ubuntu / Debian:  ./install.sh
```

- Windows は `windows/winget/packages.json` を正本として GUI アプリのみを winget で導入します。npm/pnpm manifest は独立した空配列として保持します。
- `install.cmd` は既存の PowerShell と winget で GUI アプリを導入した後、NixOS-WSL の導入と NixOS/Home Manager 適用を行います。実行順序は `taskfiles/install/taskfile.yml` が管理し、Task がなければ専用 cache に取得します。`-UserPhaseOnly` は GUI のみです。WSL 基盤の有効化だけ UAC 昇格します。Windows の CLI ツール・Node.js・npm・pnpm・dsh・AutoHotkey・GlazeWM、chezmoi、CLI runtime acceptance は導入・実行しません。既存アプリや Startup shortcut は自動削除しません。
- Codex CLI はどの OS でも個別導入せず、ChatGPT アプリ付属の CLI を使います。Windows の GUI profile は Microsoft Store のデスクトップアプリを対象とし、npm/pnpm パッケージを導入しません。
- macOS は nix-darwin が Home Manager と nix-homebrew formula/cask を同じ switch に含めます。
- 非 NixOS Linux（Ubuntu/Debian など）は standalone Home Manager がユーザー環境を適用します。Docker や OS service は管理しません。
- NixOS は NixOS generation に Home Manager と system module を統合します。

アプリと OS 設定はこの OS 別構成を唯一の通常インストール入口とします。
`full`、`minimal`、カテゴリ別などの独立した Nix profile 用パッケージ集合は
公開しません。Tart の macOS guest も通常の `install.sh` を使います。
CI は OS configuration を build することで、その構成に含まれるアプリも検証します。
standalone Home Manager は上記の OS 統合を使えない環境向けに維持します。
Windows のキー設定生成と Darwin custom package の出力は `nix/outputs.nix` に定義します。

macOS の `nrs` は nix-darwin を通じて Nix/Home Manager と宣言済み Homebrew package を反映します。通常の CLI と Neovim・WezTerm は Nix 側で管理し、cask/formula は Darwin host に明示します。Nix パッケージの版は `flake.lock` に従います。

### macOS の旧 provider サポート終了

旧 Homebrew provider を検出し、Nix provider の検証後に uninstall する
一度限りの自動移行は終了しました。通常インストールは現行 module の
導入定義を反映します。個別の移行処理ではなく、以下の宣言外パッケージの
クリーンアップを適用します。
旧 provider の metadata、移行処理、互換コマンドは提供しません。

### 自動クリーンアップ

- Nix の GC は週1回、`--delete-old` 付きで実行します。各 profile の現行世代だけを残し、
  旧世代と未参照の store path を削除します。削除した世代へのロールバックはできません。
- nix-darwin / NixOS / NixOS-WSL はシステム側の GC、standalone Home Manager は
  標準のユーザー GC を使い、二重にスケジュールしません。
- macOS は `homebrew.onActivation.cleanup = "zap"` により、設定反映時に生成 Brewfile にない
  Homebrew package を削除します。cask はその `zap` 定義に記載された設定・データも削除します。
  宣言から外す操作や module の無効化でデータを失う可能性があり、再インストールだけでは
  復元できません。手動インストールしたアプリや Mac App Store アプリは対象外です。
- この設定は任意のユーザーファイルやアプリのデータ全般を走査・削除するものではありません。

通常インストールは Nix のビルド・activation、ユーザー設定の反映、環境の動作確認を行います。
application identity、署名、CLI version を独自の期待値と比較する provider 検証は廃止しました。
パッケージ更新時のダウンロード hash 確認と Nix candidate の評価・ビルドは維持します。

非 NixOS Linux も `./install.sh` が通常の入口です。Home Manager の適用に追加の opt-in は不要です。

macOS で Homebrew cask の適用に失敗する場合は、
[Homebrew cask のトラブルシューティング](./homebrew-cask-troubleshooting.md)
を参照してください。

## Windows manifest

`windows/winget/packages.json` は直接編集する独立した正本です。package ID、Store source、PATH、検証条件、個別 timeout などは、このファイルの既存 schema に合わせます。Unix module に Windows の install metadata は置きません。

Windows の package install timeout は 3600 秒を共通既定値とし、WinGet manifest と direct installer に使います。npm/pnpm/WinGet/WSL の runtime adapter も既定 3600 秒で、`DOTFILES_INSTALL_TIMEOUT_SECONDS` による上書きを維持します。direct installer でも環境変数を manifest の値より優先し、0 はダウンロードと外部プロセスのタイムアウトを無効にします。不正な環境変数値や負数は無視し、manifest の個別 timeout、未指定なら共通既定値を使います。

起動検証の既定と WSL の検証は 120 秒です。既存の長い個別 timeout は短縮せず、manifest の個別値を優先します。

Windows の npm/pnpm manifest は空で、dsh、pnpm、Bun、Codex CLI の個別導入は行いません。Codex CLI は ChatGPT アプリ付属のものを使います。

## システム package と Home Manager の境界

| 対象                                             | 管理先                                                           |
| ------------------------------------------------ | ---------------------------------------------------------------- |
| shell / editor から使う Unix CLI                 | `nix/modules/tools.nix` の `programs.*.enable` / `home.packages` |
| Docker daemon/socket、ユーザー group、OS service | NixOS / nix-darwin host                                          |
| macOS CLI                                        | 原則 Nix/Home Manager、明示例外は Homebrew formula               |
| macOS GUI application                            | Home Manager / system module の Nix package と Homebrew cask     |
| Windows GUI/OS application                       | `windows/winget/packages.json` と winget/msstore handler         |
| shell、Git、terminal、editor 設定                | Unix は Home Manager、Windows は chezmoi                         |

同じ package を Home Manager と system layer の両方へ重複させるのは、system service が絶対 path を必要とする場合に限定します。

Node.js/npm と dsh は `nix/modules/tools.nix` が導入します。`hermes:gmail:auth` が呼ぶ `scripts/sh/hermes-gmail.sh` の `npx` は、この公開 PATH の Node.js/npm を使います。Hermes 自身の専用 Node runtime は upstream wrapper が提供します。dsh は upstream Nix package を使用します。Codex は設定だけを管理し、CLI は ChatGPT アプリ付属のものを使います。

ChatGPT は `nix/modules/ai_agents/chatgpt/` で macOS のアプリと同梱 Codex の設定をまとめます。Windows の Store ID・導入・検証情報は `windows/winget/packages.json` が所有します。

1Password の CLI は `nix/modules/tools.nix`、デスクトップ版と SSH agent 設定は `nix/modules/1password/` が管理します。`default.nix` が Home Manager の Linux デスクトップ版、`ssh.nix` が公式 SSH agent socket の `IdentityAgent` / `SSH_AUTH_SOCK`、`darwin-system.nix` が macOS システムのデスクトップ版を担当します。Git 署名コマンドと WSL の Windows 連携は host に残します。

Git / ghq の導入は `nix/modules/tools.nix`、設定は `nix/modules/git/` にまとめます。`default.nix` は Home Manager 標準 `programs.git` の設定、`ghq.nix` は共通の `ghq.root`、`gtr.nix` は既存の Git alias を管理します。署名と WSL の保存先の差分は host に残します。

lazygit / Herdr の有効化は `nix/modules/tools.nix` に置きます。`nix/modules/lazygit/` は Bash / Zsh の `lg` 連携、`nix/modules/herdr/` は `config.toml` を読み込む標準 `settings` を管理します。Windows の既存 Herdr installer・chezmoi 設定は維持します。

エディタの設定は `nix/modules/editors/` にまとめます。Neovim 本体・補助 CLI・LSP・プラグイン実行依存の導入は `nix/modules/tools.nix`、設定とプラグインは `nvim/` が管理します。プラグインが宣言する実行依存も tools が Home Manager の設定から集め、通常の PATH に導入します。Orca の `default.nix` は Home Manager にアプリを導入し、`package.nix` が macOS の公式 DMG と Linux の公式 AppImage を選択します。Linux の FHS 環境・デスクトップ登録・公式 `orca-ide` CLI は `linux.nix`、バージョン・URL・ハッシュは `sources.json` が管理します。LSP・整形ツールは全エディタ共通で `nix/modules/tools.nix` から PATH に導入します。運用は [Neovim](../chezmoi/neovim.md) を参照してください。

zoxide / fzf / eza / bat / ripgrep の導入は `nix/modules/tools.nix`、ユーザー設定は `nix/home/shells/plugins/` に置きます。zoxide は標準連携の `--cmd cd` で `cd` / `cdi` を使い、WSL の除外ディレクトリは host が管理します。fzf の Zsh は標準 integration の Ctrl+T/R・Alt+C を使い、Unix の Bash integration は無効です。ripgrep の設定ファイルと `RIPGREP_CONFIG_PATH` は Home Manager が生成します。Windows の Bash 設定は chezmoi の既存設定を使います。

Starship は `nix/modules/tools.nix` で有効化します。プロンプトは `nix/modules/shells/plugins/starship/` の `programs.starship.settings` に定義し、Home Manager が `~/.config/starship.toml` を生成します。

## 関連ファイル

- `nix/modules/`
- `nix/hosts/`
- `nix/home/common.nix`
- `nix/home/keybindings/`
- `nix/outputs.nix`
- `windows/{winget,npm,pnpm}/packages.json`
- `scripts/powershell/handlers/Handler.Winget.ps1`
- `scripts/sh/update-darwin-providers.sh`
