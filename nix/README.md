# Nix レイアウト

## 所有境界

| パス                    | 所有範囲                                                            |
| ----------------------- | ------------------------------------------------------------------- |
| `nix/defaults.nix`      | OS 基盤設定、型付き option による有効化、公開構成、GC               |
| `nix/modules/`          | Unix のパッケージ導入・アプリ設定・custom package 定義              |
| `windows/winget/`       | Windows GUI の独立した install manifest                             |
| `nix/home/keybindings/` | 共通 action/key と Windows export                                   |
| `nix/home/`             | 共通キー配列と Windows export                                       |
| `nix/tests/unit/`       | nix-unit による Nix 式・実効設定値のテスト                          |
| `nix/tests/build/`      | `*.check.nix` による named derivation の属性セット                  |
| `nix/tests/fixtures/`   | テスト用の共有入力・補助 module                                     |
| `chezmoi/`              | Windows の dotfile、テンプレート、アプリ設定。Unix 設定は配布しない |

- host / hardware 設定を `nix/home/` に置かない。
- Home Manager と chezmoi で同じファイルを所有しない。

Unix CLI / GUI はアプリごとの module が導入・package 選択・設定・連携・専用の実行依存を所有します。enable・単純な package list・単一代入だけなら必要な構成へ直接書きます。共通・OS 別構成は module の外で組み立て、Windows の導入情報は独立した manifest が所有します。
詳細は [分割の理由と編集先](../docs/nix/package-management.md#分割の理由と編集先) を参照してください。
キー配列は `home/keybindings/bindings.nix`、AeroSpace と Hyprland の設定・生成関数は
`modules/aerospace/` と `modules/hyprland/` が管理し、`defaults.nix` が OS ごとの型付き enable option を指定します。
Windows は標準デスクトップを使用し、Nix から設定を生成・配布しません。WSL guest と standalone Linux へ
Hyprland を自動導入しない設計です。[対応範囲・移行状況と検証](../docs/chezmoi/omarchy.md) を参照してください。

秘密情報はリポジトリや Nix モジュールに書かない。既存の 1Password / chezmoi テンプレートまたは
実行時環境変数を使い、秘密の値を Nix store に入れない。

## 設定の配置

1. アプリの設定・サービス・activation は `modules/`、OS 基盤設定と型付き option による有効化は `defaults.nix` に置く。
   統合構成と standalone は同じ OS の Home Manager module を使う。
   基本フォントは統合時にはシステム、standalone 時には Home Manager が導入する。
2. system、アカウント、OS 別の enable optionは `defaults.nix` の `systemDefaults` にまとめる。
   アカウントは各 OS ブロックに明示し、公開構成は末尾の `configurations` に登録する。
   共通設定と OS 別の enable option を記載し、末尾の構成登録で `specialArgs.platform` を選択する。
   共通の Lix・OS GC・Home Manager 接続は `systemDefaults`、GC 日時は各 OS ブロックに置く。
   CPU は `system` 引数で選択する。
3. Home Manager の共通・OS 別設定は同じ `systemDefaults.home-manager.sharedModules` に宣言し、standalone も再利用する。
4. Unix のパッケージは `nix/modules/` のアプリごとの module に宣言し、標準の `programs.*.enable` または `home.packages` と設定・連携を一緒に管理する。enable・単純な package list・単一代入だけなら `defaults.nix` の必要な構成へ直接書く。設定・package override・生成・連携を持つアプリは module にまとめる。Neovim の LSP・整形ツール・toolchain は Neovim が所有する。通常の CLI・GUI は Home Manager、OS 固有の設定・権限・システムサービス・連携は `defaults.nix`、Homebrew と cask は `defaults.nix` が担当する。Windows は `windows/winget/packages.json` を直接編集する。
5. Unix の dotfile は Home Manager、Windows は `chezmoi/`、秘密情報は既存の secret 経路を使い、所有を重複させない。
6. Nix 設定の変更は `nix flake check --all-systems --no-build --no-write-lock-file` で評価し、
   対象 system の `nix-unit` と関連 build check を build して検証する。
   Bats は installer、shell、外部プロセス、runtime 契約に限って実行する。
   Nix package 選択と module の実効設定値は `nix/tests/unit/` の nix-unit が所有し、Bats は
   [テスト分類](tests/README.md) に記載した runtime / artifact 契約を保持する。WSL の初回同期は PowerShell が担当し、rebuild は直接呼び出す。

   Repository-owned custom derivations は `checks.*.custom-package-builds` を build して確認する。
   この check は Dia、Neovim、Orca の supported system だけを対象にし、
   upstream nixpkgs package 全体や privileged activation は実行しない。

   `nix/tests/discover.nix` が unit `*.nix` / build `*.check.nix` を自動検出し、`nix/tests/default.nix` が flake に接続する。個別のテスト登録は不要。nix-unit も flake の `checks` 経由で実行する。
   `--no-build` の成功はテスト実行の成功を意味しない。[配置と実行方法](tests/README.md) を参照する。

構成登録は `nix/defaults.nix:configurations`、app と package は `perSystem` にまとめます。
ユーザー名・stateVersion は `systemDefaults` 内の `defaults` で一元管理します。
OS 設定は `systemDefaults` が所有し、Hyprland は native Linux 構成だけが有効化します。

Dock・Finder・trackpad の設定と反映は `modules/desktop/default.nix`、Dock の固定アプリは `modules/dock/default.nix` が管理します。
`nix/modules/` は共通のアプリ・機能単位に分け、OS 固有の設定は `defaults.nix` の各 OS ブロックに置きます。すべての実 module の `default.nix` を `discover-modules.nix` が自動検出し、`defaults.nix` は型付き option で有効化します。通常は Home Manager、`nixos/` / `darwin/` / `system/` 配下はそれぞれの OS scope とし、アプリごとの import パス登録・公開一覧は不要です。純粋な factory・renderer は通常の関数として利用し、自動検出しません。

## Codex CLI

ChatGPT アプリ付属の Codex CLI と、設定管理の責務分担は
[`docs/nix/codex-cli.md`](../docs/nix/codex-cli.md) を参照する。
