# Nix レイアウト

| パス                             | 所有範囲                                              |
| -------------------------------- | ----------------------------------------------------- |
| `defaults.nix`                   | flake 出力の接続                                      |
| `modules/formatters/default.nix` | formatter・開発シェル・PowerShell lint                |
| `home/configurations.nix`        | Home Manager 構成の登録                               |
| `hosts/configurations.nix`       | OS 構成の登録                                         |
| `modules/nix/settings.nix`       | 共通 Nix ポリシーとキャッシュ                         |
| `home/settings.nix`              | Home Manager のユーザー名                             |
| `home/common.nix`                | 共通ユーザー基盤設定                                  |
| `home/default.nix`               | 共通 Home Manager module の読み込み                   |
| `hosts/default.nix`              | 共通 OS 設定、timezone、Nix daemon、Home Manager 接続 |
| `hosts/darwin/`                  | macOS の OS 基盤設定                                  |
| `hosts/linux/`                   | NixOS / Linux の OS 基盤設定                          |
| `hosts/wsl/`                     | NixOS-WSL の OS 基盤設定                              |
| `modules/`                       | アプリ固有の設定・package 選択・連携・実行依存        |
| `home/keybindings/`              | 共通 action/key と Windows export                     |
| `tests/unit/`                    | nix-unit による Nix 式・実効設定値のテスト            |
| `tests/build/`                   | ビルドと実行契約を検証する derivation                 |
| `tests/fixtures/`                | テスト用の共有入力・補助 module                       |

通常の CLI・GUI とユーザー設定は Home Manager、OS 基盤設定は hosts が所有します。
共通アプリ module は `nix/modules/default.nix`、アプリ内の子 module はその親、OS 固有の module は各 hosts の `imports` に明示します。統合環境と通常の Linux は同じ `nix/home/default.nix` を使います。
各アプリ module が原則 `programs.<name>.enable = true` を宣言します。各 stateVersion は root の `flake.nix` に一元化します。
Neovim の LSP・整形ツール・toolchain は Neovim module に置きます。

OS 統合環境と通常の Linux などの Home Manager 単独構成は同じ `home/default.nix` を使います。
OS 統合時の nix.conf と GC は OS、Home Manager 単独構成では Home Manager が所有し、二重生成しません。
native NixOS だけが Hyprland を有効化し、WSL / 通常の Linux には compositor を自動導入しません。
hardware configuration が存在する場合だけ native NixOS 構成を公開します。

Unix の設定ファイルは Home Manager、Windows は `chezmoi/`、Windows GUI の導入は
`chezmoi/winget/packages.json` が所有します。秘密情報をリポジトリや Nix store に入れません。

検証は [Nix テスト](tests/README.md)、所有境界は
[パッケージ管理](../docs/nix/package-management.md)、Codex CLI は
[専用ドキュメント](../docs/nix/codex-cli.md) を参照してください。
