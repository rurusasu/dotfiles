# Home Manager の構成

`nix/home/keybindings/` は共通の `bindings.nix`、Windows 向け `generated.json` と `windows-export.nix` を保持します。
アプリの設定・サービス・キー設定生成関数は `nix/modules/`、OS の基盤設定と module 選択は `nix/defaults.nix` が担当します。

enable・単純な package list・単一代入だけなら `nix/defaults.nix` の必要な構成へ直接書きます。設定・package override・生成・連携を持つアプリは module にまとめます。

| 設定                                  | 所有先                                                                                |
| ------------------------------------- | ------------------------------------------------------------------------------------- |
| CLI / GUI の導入・設定・連携          | `../modules/` のアプリごとの module                                                   |
| 1Password・署名・WSL interop          | `../modules/1password/`                                                               |
| Git・ghq・gwq                         | `../modules/git/`                                                                     |
| Bash・共通 PATH・Zsh                  | `../modules/shells/`                                                                  |
| Starship・Patina・zoxide              | `../modules/shells/plugins/`                                                          |
| AeroSpace・Hyprland                   | `../modules/aerospace/`・`../modules/hyprland/`                                       |
| Ghostty・Neovim のキー設定            | `../modules/terminals/ghostty/`・`../modules/editors/nvim/`                           |
| fcitx5・gnome-keyring・VS Code Server | `../modules/fcitx5.nix`・`../modules/gnome-keyring/`・`../modules/editors/vscode.nix` |
| Homebrew 設定                         | `../defaults.nix`                                                                     |

Dock・Finder・trackpad と反映処理は `../modules/desktop.nix`、WSLg フォント配布は `../defaults.nix` の WSL 設定が担当します。

`defaults.nix` は共有宣言、OS 別の基盤設定、末尾の OS 選択と公開構成の順に記載します。
アプリ固有の option や activation は各 module に置きます。
WSLg の表示環境・portal・nix-ld は OS 基盤設定として残します。

## ユーザーと GC

ユーザー名・stateVersion は `systemDefaults` 内の `defaults` で一元管理します。
Darwin は `system.primaryUser`、WSL は上書き可能な `wsl.defaultUser` を通じて参照します。
統合 Home Manager は OS のユーザー名・ホーム・Nix package を標準継承します。

共通の Lix・GC・Home Manager 設定は一つの `systemDefaults` にまとめ、ユーザー設定は同 module の `home-manager.sharedModules` に宣言します。
同じ `sharedModules` 内で OS 別設定を選択し、standalone もそのまま再利用します。OS は末尾の構成登録の `platform` で指定します。
Go / uv の独自 cache 整理ジョブは設けません。Neovim が使う Go toolchain は `../modules/editors/nvim/runtime.nix`、uv は `../defaults.nix` が導入します。
Hermes は同梱 Python を使い、プロジェクト依存は uv で管理します。

## 検証

Nix option・package・構成は `nix/tests/unit/`、生成物と実行契約は `nix/tests/build/` で検証します。
全 OS の flake 評価と対象 system の nix-unit・関連 build check を実行します。
Bats は shell / installer / 外部プロセスに限定します。[Nix テスト](../tests/README.md)を参照してください。
