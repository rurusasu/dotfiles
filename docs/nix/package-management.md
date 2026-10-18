# パッケージ管理

## 管理方針

Unix CLI の PATH への導入は `nix/modules/tools.nix` にまとめます。CLI の Home Manager 標準 `programs.*.enable` と、設定をユーザーが管理する CLI・標準 module のない CLI・LSP・プラグイン実行依存の `home.packages` をここに宣言します。Linux / WSLg GUI は `desktop.nix`、Darwin system GUI は `desktop-darwin.nix` を所有先とし、各アプリ module は設定・連携・package override を担当します。`nix/home/common.nix` が tools の `homeManager` と設定 module を import します。

`tools.nix` は通常の Home Manager module 一つではなく、`homeManager`、`darwin` と既存のアプリ有効化 module を公開します。`desktop.nix` は Home Manager 向けの `linuxDesktop` / `wslDesktop` を公開し、`desktop-darwin.nix` は nix-darwin 向けの通常 module です。対象 host / 設定 module が必要な scope を選択し、OS の option を混在させません。

Python のユーザー環境は `uv` で管理し、`tools.nix` は uv を導入します。Python interpreter は直接 `home.packages` に追加しません。Darwin の package updater と X API 同期の公開コマンドは `uv run --no-project --managed-python --python 3.14 python ...` を使います。Hermes bootstrap など、Nix の構築・実行に閉じた専用 Python 依存は各 module が管理します。

Chrome / Obsidian / 1Password GUI の Linux 導入と WSL の Spotify / Signal は `desktop.nix` に宣言します。Darwin の system GUI は `desktop-darwin.nix` に宣言します。今回の分離対象外である既存の ChatGPT / Orca / terminal / Discord / native desktop selector は `tools.nix` に残っています。新しい GUI の追加先は前述の desktop module とし、既存 selector と設定 module の配線を混同しません。OS service、フォント、ビルド用依存はそれぞれの module / host で管理します。設定・サービスから絶対 store path で呼び出す専用の実行依存は、その設定・サービスの module に宣言します。

Windows の導入情報は `windows/winget/packages.json` を直接管理します。Unix の Nix module と独立した正本で、Nix から生成しません。通常の Windows セットアップは GUI アプリだけを導入し、`windows/npm/packages.json` と `windows/pnpm/packages.json` は空です。

フォントパッケージと fontconfig 設定は `nix/modules/fonts.nix` の `fonts.packages` / `fonts.fontconfig` に一度だけ定義します。Darwin / NixOS のシステム構成はそれぞれ `nix/hosts/aarch64-darwin/platform.nix` / `nix/hosts/shared/nixos/platform.nix` を読み込み、OS 固有の option と配線はこの入口に記載します。NixOS は共通 module を import し、NixOS 専用の `fonts.fontDir.enable` を設定します。Darwin は `fonts.packages` を nix-darwin に渡し、`nix/hosts/aarch64-darwin/home.nix` が `fonts.fontconfig` を設定します。Linux / WSL と standalone Darwin の Home Manager は各 entrypoint から共通定義を直接参照します。standalone Darwin のフォント配布は Home Manager 標準機能を使います。

共通の `fonts.fontconfig.defaultFonts` は `monospace` / `sansSerif` / `serif` を `UDEV Gothic NF`、`emoji` を `Noto Color Emoji` に設定します。Darwin での既定フォント設定は fontconfig を使うアプリに適用され、macOS 標準 UI / CoreText の既定フォントは変更しません。

## 分割の理由と編集先

Unix CLI の導入は `tools.nix`、Linux / WSLg GUI は `desktop.nix`、Darwin system GUI は `desktop-darwin.nix`、設定・連携はアプリ・機能ごとの module にまとめます。Windows の manifest、OS の service、有効化、ユーザー設定は、それぞれを適用する層が管理します。

| 編集先                                               | 責務                                                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `nix/modules/tools.nix`                              | Unix CLI の導入。既存の未分離 GUI selector も現在ここに残る                           |
| `nix/modules/desktop.nix`                            | Linux の Chrome / Obsidian / 1Password GUI / ComfyUI Desktop、WSL の Spotify / Signal |
| `nix/modules/desktop-darwin.nix`                     | Darwin system GUI の Dia / Obsidian / Raycast / 1Password / ComfyUI Desktop           |
| `nix/modules/<app>/`                                 | アプリの設定・連携・package override、custom package 定義                             |
| `nix/modules/ai_agents/hermes/bootstrap.nix`         | Hermes bootstrap の package 構築。CLI の導入は tools、サービス用依存は Hermes module  |
| `nix/modules/browsers/dia/`                          | Dia の package 選択関数、`package.nix`、更新用 `provider-candidates.nix`              |
| `nix/modules/shells/powershell/psscriptanalyzer.nix` | formatter が使用する PSScriptAnalyzer の package 定義                                 |
| `nix/hosts/`                                         | module の選択、OS の service / 有効化・競合解除                                       |
| `nix/home/`                                          | OS 非依存の Home Manager 共通設定と module の読み込み                                 |
| `nix/home/keybindings/`                              | 共通キー配置・設定生成関数・ユーザー設定                                              |
| `windows/winget/packages.json`                       | Windows GUI の package ID、導入・検証情報                                             |
| `windows/{npm,pnpm}/packages.json`                   | 独立した Node package manifest。現在は空                                              |
| `nix/outputs.nix`                                    | Darwin custom package の build 出力                                                   |

各 host の `home.nix` は `nix/home/common.nix` を通じて CLI 導入とアプリ設定を読み込みます。Darwin host は `tools.nix` の `darwin` と `desktop-darwin.nix`、Linux host は `desktop.nix` の `linuxDesktop`、NixOS-WSL は `wslDesktop` を読み込みます。Darwin のブラウザーは Dia、Linux / WSLg は Chrome を使います。WSL は Chrome / Spotify / Signal / Obsidian / 1Password GUI を Nix で導入し、デスクトップキーから WSLg で開きます。Windows の 1Password CLI / Git signer 連携は維持します。

Homebrew は host が設定します。native NixOS の Hyprland は host が有効化し、Firefox / fuzzel / Nautilus は既存の `tools.nix.nativeDesktop` が導入します。WSL / standalone へ compositor を自動導入しません。Discord も Darwin / native Linux の既存 Home Manager module から導入し、WSL では Windows のアプリを利用します。

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

Linux / WSLg GUI は `desktop.nix` の対象 scope、Darwin system GUI は `desktop-darwin.nix` に追加します。Homebrew と OS service は host module に定義します。Windows に追加する場合は `windows/winget/packages.json` を直接編集し、導入・検証情報を同じ entry に記述します。

## OS ごとの反映

通常は個別コマンドではなく one-command installer を再実行します。

```text
Windows:          install.cmd
macOS:            ./install.sh
NixOS:            ./install.sh
Ubuntu / Debian:  ./install.sh
```

- Windows は `windows/winget/packages.json` を正本として GUI アプリのみを winget で導入します。npm/pnpm manifest は独立した空配列として保持します。
- `install.cmd` は既存の PowerShell と winget で Windows GUI アプリを導入した後、NixOS-WSL の導入、NixOS/Home Manager 適用、Windows chezmoi の順に実行します。WSLg の対象 GUI は Nix 側で導入します。実行順序は `taskfiles/install/taskfile.yml` が管理し、Task がなければ専用 cache に取得します。`-UserPhaseOnly` は Windows GUI のみです。WSL 基盤の有効化だけ UAC 昇格します。Node.js・npm・pnpm・dsh・AutoHotkey・GlazeWM の Windows 導入や CLI runtime acceptance は行いません。既存アプリや Startup shortcut は自動削除しません。
- Codex CLI はどの OS でも個別導入せず、各 OS 向け ChatGPT アプリ付属の CLI を使います。Windows の GUI profile は Microsoft Store のデスクトップアプリを対象とし、npm/pnpm パッケージを導入しません。
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

### macOS の権限エラー

Nix / Home Manager / Homebrew の適用で権限エラーが出た場合は、macOS の設定画面で
実行元の端末アプリに必要な「アプリ管理」または「フルディスクアクセス」を許可してください。
macOS が再起動を求めたら端末アプリを `⌘Q` で終了して開き直し、`./install.sh` を再実行します。
Homebrew の `zap` や設定ファイルの配置で停止した場合の詳細は
[Homebrew cask のトラブルシューティング](./homebrew-cask-troubleshooting.md#フルディスクアクセス)を参照してください。

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
- macOS の activation は GarageBand・iMovie・Pages・Numbers・Keynote のアプリ本体も削除します。
  `/Applications` 内の指定名と bundle ID が一致するものだけを対象とし、対象が存在しなければ何もしません。
  symlink や異なるアプリを検出した場合は削除前に停止します。書類・設定・音源などのユーザーデータは削除しません。
  `/System` 内のアプリと Safari は macOS の保護対象として削除対象に含めません。

Dock の固定アプリと順序は `nix/hosts/aarch64-darwin/system.nix` で管理します。
アプリ・ChatGPT・Dia・Ghostty・Hermes・Obsidian の順に固定し、追加の固定フォルダーと最近使ったアプリは表示しません。
Finder・ゴミ箱・起動中のアプリの表示は固定アプリの一覧とは別です。

通常インストールは Nix のビルド・activation、ユーザー設定の反映、環境の動作確認を行います。
application identity、署名、CLI version を独自の期待値と比較する provider 検証は廃止しました。
パッケージ更新時のダウンロード hash 確認と Nix candidate の評価・ビルドは維持します。

非 NixOS Linux も `./install.sh` が通常の入口です。Home Manager の適用に追加の opt-in は不要です。

macOS で Homebrew cask の適用に失敗する場合は、
[Homebrew cask のトラブルシューティング](./homebrew-cask-troubleshooting.md)
を参照してください。

## ComfyUI Desktop

ComfyUI Desktop は Apple Silicon macOS と x86_64 Linux / WSLg に導入します。
`nix/modules/comfyui/package.nix` に公式バイナリのバージョン・ビルド固定 URL・ハッシュを記録します。
macOS は署名済み `.app` を維持し、Linux は AppImage を FHS 環境で起動します。
公式の ARM64 Linux バイナリがないため、aarch64-linux には追加しません。
配布元は [Comfy Desktop](https://github.com/Comfy-Org/Comfy-Desktop) です。

アプリ本体の更新は `package.nix` の配布情報の更新と通常の Nix 設定反映で行います。
モデル・カスタムノード・ComfyUI の実行環境は、Desktop が管理する書き込み可能なユーザーデータです。
これらの内容やバージョンは Nix で固定しません。アプリ内更新は Nix store に書き込めないため、
アプリの設定で自動インストールを無効にし、Nix 側で更新してください。
GUI 起動と GPU 推論の確認には対象 OS の実機が必要です。

## Windows manifest

`windows/winget/packages.json` は直接編集する独立した正本です。package ID、Store source、PATH、検証条件、個別 timeout などは、このファイルの既存 schema に合わせます。Unix module に Windows の install metadata は置きません。

Chrome / Spotify / Signal / Obsidian の通常導入とキーからの起動先は NixOS-WSL に統一します。これらを Windows manifest から外しても、導入済みの Windows 版は自動 uninstall しません。Windows の PowerToys は host のキー操作、Windows 版 1Password は既存の `op.exe` / Git signer 連携のため維持します。1Password GUI の通常起動先は WSLg です。

Windows の package install timeout は 3600 秒を共通既定値とし、WinGet manifest と direct installer に使います。npm/pnpm/WinGet/WSL の runtime adapter も既定 3600 秒で、`DOTFILES_INSTALL_TIMEOUT_SECONDS` による上書きを維持します。direct installer でも環境変数を manifest の値より優先し、0 はダウンロードと外部プロセスのタイムアウトを無効にします。不正な環境変数値や負数は無視し、manifest の個別 timeout、未指定なら共通既定値を使います。

起動検証の既定と WSL の検証は 120 秒です。既存の長い個別 timeout は短縮せず、manifest の個別値を優先します。

Windows の npm/pnpm manifest は空で、dsh、pnpm、Bun、Codex CLI の個別導入は行いません。Windows は Windows アプリ付属 CLI を、NixOS / WSL は Linux アプリ付属 CLI を使います。

Windows Dia は WinGet / Microsoft Store 未登録のため、同じ manifest の `direct` source に公式 Windows 11 x64 MSIX を宣言します。URL・SHA256・package identity と依存関係を固定し、導入済みの同等以上の package を検証して利用します。Windows の export もこの宣言を保持します。更新時は公式配布から version・URL・hash と依存 metadata を確認して変更します。

## システム package と Home Manager の境界

| 対象                                             | 管理先                                                           |
| ------------------------------------------------ | ---------------------------------------------------------------- |
| shell / editor から使う Unix CLI                 | `nix/modules/tools.nix` の `programs.*.enable` / `home.packages` |
| Linux / WSLg GUI                                 | `nix/modules/desktop.nix`                                        |
| Darwin system GUI                                | `nix/modules/desktop-darwin.nix`                                 |
| Docker daemon/socket、ユーザー group、OS service | NixOS / nix-darwin host                                          |
| macOS CLI                                        | 原則 Nix/Home Manager、明示例外は Homebrew formula               |
| macOS GUI application                            | Home Manager / system module の Nix package と Homebrew cask     |
| Windows GUI/OS application                       | `windows/winget/packages.json` と winget/msstore handler         |
| shell、Git、terminal、editor 設定                | Unix は Home Manager、Windows は chezmoi                         |

同じ package を Home Manager と system layer の両方へ重複させるのは、system service が絶対 path を必要とする場合に限定します。

Node.js/npm と dsh は `nix/modules/tools.nix` が導入します。`hermes:gmail:auth` が呼ぶ `scripts/sh/hermes-gmail.sh` の `npx` は、この公開 PATH の Node.js/npm を使います。Hermes 自身の専用 Node runtime は upstream wrapper が提供します。dsh は upstream Nix package を使用します。Codex の設定は Home Manager が管理し、NixOS / WSL は Linux アプリ付属 CLI、Windows は Windows アプリ付属 CLI を使います。

ChatGPT アプリと同梱 Codex CLI は `tools.nix` で OS ごとに選択し、`nix/modules/ai_agents/chatgpt/` が Codex の設定を管理します。WSL は Linux CLI のみを選び、GUI を導入しません。Windows の Store ID・導入・検証情報は `windows/winget/packages.json` が所有します。

1Password CLI の導入は `nix/modules/tools.nix`、Linux GUI は `desktop.nix`、Darwin system GUI は `desktop-darwin.nix`、公式 SSH agent socket の `IdentityAgent` / `SSH_AUTH_SOCK` は `nix/modules/1password/ssh.nix` が管理します。Git 署名コマンドと WSL の Windows 連携は host に残します。WSLg GUI の起動先を変えても、Windows `op.exe` / signer 連携の認証方式は変更しません。

Git / ghq の導入は `nix/modules/tools.nix`、設定は `nix/modules/git/` にまとめます。`default.nix` は Home Manager 標準 `programs.git` の設定、`ghq.nix` は共通の `ghq.root`、`gtr.nix` は既存の Git alias を管理します。署名と WSL の保存先の差分は host に残します。

lazygit / Herdr の有効化は `nix/modules/tools.nix` に置きます。`nix/modules/lazygit/` は Bash / Zsh の `lg` 連携、`nix/modules/herdr/` は標準 `programs.herdr.settings` に Nix で設定値を直接定義します。Windows の既存 Herdr installer・chezmoi 設定は維持します。

エディタの設定は `nix/modules/editors/` にまとめます。Neovim 本体・補助 CLI・LSP・プラグイン実行依存の導入は `nix/modules/tools.nix`、設定とプラグインは `nvim/` が管理します。プラグインが宣言する実行依存も tools が Home Manager の設定から集め、通常の PATH に導入します。Orca の導入は `tools.nix`、`editors/orca/package.nix` が macOS の公式 DMG と Linux の公式 AppImage を選択し、バージョン・URL・ハッシュも同じファイルで管理します。Linux の FHS 環境・デスクトップ登録・公式 `orca-ide` CLI は `linux.nix` が担当します。LSP・整形ツールは全エディタ共通で `nix/modules/tools.nix` から PATH に導入します。運用は [Neovim](../chezmoi/neovim.md) を参照してください。

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
