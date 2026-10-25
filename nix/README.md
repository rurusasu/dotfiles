# Nix レイアウト

## 所有境界

| パス                    | 所有範囲                                                            |
| ----------------------- | ------------------------------------------------------------------- |
| `nix/default.nix`       | OS / Home Manager 設定、ホスト情報、構成生成・登録、GC              |
| `nix/modules/`          | Unix のパッケージ導入・アプリ設定・custom package 定義              |
| `windows/winget/`       | Windows GUI の独立した install manifest                             |
| `nix/home/keybindings/` | 共通 action/key、純粋な設定生成関数、Home Manager のユーザー設定    |
| `nix/home/`             | キー配列の補助定義と WSL の署名スクリプト                           |
| `nix/tests/unit/`       | nix-unit による Nix 式・実効設定値のテスト                          |
| `nix/tests/build/`      | ビルド・生成物比較・外部プロセス・VM テストの derivation            |
| `nix/tests/fixtures/`   | テスト用の共有入力・補助 module                                     |
| `chezmoi/`              | Windows の dotfile、テンプレート、アプリ設定。Unix 設定は配布しない |

- host / hardware 設定を `nix/home/` に置かない。
- Home Manager と chezmoi で同じファイルを所有しない。

Unix CLI / GUI の導入は `nix/modules/tools.nix`、設定・連携は機能ごとの module、Windows の導入情報は独立した manifest、OS の動作は host に分けます。
詳細は [分割の理由と編集先](../docs/nix/package-management.md#分割の理由と編集先) を参照してください。
キー配列は home のユーザー設定と hosts の OS 統合に分けます。Darwin の AeroSpace と
ユーザー shortcut は `home/keybindings/darwin.nix` が管理し、native NixOS は
`default.nix` の `hostModules.linux` から Home Manager module を選択します。
Windows は標準デスクトップを使用し、Nix から設定を生成・配布しません。WSL guest と standalone Linux へ
Hyprland を自動導入しない設計です。[対応範囲・移行状況と検証](../docs/chezmoi/omarchy.md) を参照してください。

秘密情報はリポジトリや Nix モジュールに書かない。既存の 1Password / chezmoi テンプレートまたは
実行時環境変数を使い、秘密の値を Nix store に入れない。

## 設定の配置

1. Home Manager の共通・OS 別設定と module の選択は、`default.nix` の `homeModules` に追加する。
   統合構成と standalone は同じ OS の Home Manager module を使う。
   基本フォントは統合時にはシステム、standalone 時には Home Manager が導入する。
2. system、OS サービス、アカウント、hardware の配線は `default.nix` の `hostModules` に追加する。
   native アカウント情報は`hostModules.nixos` 内の検出処理、公開構成は `configurations` が担当する。
   共通の Lix・OS GC・Home Manager 接続は `systemDefaults`、GC 日時は各 OS module に置く。
   CPU は `system` 引数で選択する。
3. OS 別の `homeModules` は `homeModules.common` を読み込む。キー配列の補助定義と
   WSL の署名スクリプトは `home/` に残し、ユーザー設定から system module を import しない。
4. Unix のパッケージは `nix/modules/` に宣言する。Unix CLI / GUI の導入はすべて `tools.nix`、GUI の OS 別選択も `tools.nix` にまとめ、個別アプリの設定・連携は各 module にまとめる。CLI / GUI の `programs.*.enable` と `home.packages` をアプリ module へ分散させない。Windows は `windows/winget/packages.json` を直接編集する。
5. Unix の dotfile は Home Manager、Windows は `chezmoi/`、秘密情報は既存の secret 経路を使い、所有を重複させない。
6. Nix 設定の変更は `nix flake check --all-systems --no-build --no-write-lock-file` で評価し、
   対象 system の `nix-unit` と関連 build check を build して検証する。
   Bats は installer、shell、外部プロセス、runtime 契約に限って実行する。
   Nix package 選択と module の実効設定値は `nix/tests/unit/` の nix-unit が所有し、Bats は
   [テスト分類](tests/README.md) に記載した runtime / artifact 契約を保持する。WSL の初回同期は PowerShell が担当し、rebuild は直接呼び出す。

   Repository-owned custom derivations は `checks.*.custom-package-builds` を build して確認する。
   この check は Dia、Neovim、Orca の supported system だけを対象にし、
   upstream nixpkgs package 全体や privileged activation は実行しない。

   テストの登録は `nix/tests/default.nix` が担当する。nix-unit も flake の `checks` 経由で実行する。
   `--no-build` の成功はテスト実行の成功を意味しない。[配置と実行方法](tests/README.md) を参照する。

構成登録は `nix/default.nix:configurations`、app と package は `perSystem` にまとめます。
native NixOS と WSL の `system.stateVersion = "26.05"` と共通 OS 設定は
`nix/default.nix:hostModules.nixos` が所有し、Hyprland は `nix/default.nix:hostModules.linux` だけが有効化します。
Darwin の system font・loginwindow defaults・timezone は `nix/default.nix:hostModules.darwin`、
Dock・Finder・trackpad などのユーザー defaults は `nix/default.nix:homeModules.darwin` が管理します。
`nix/modules/` には OS 別ディレクトリを置かず、アプリ・機能単位の共通設定だけを残します。

## Codex CLI

ChatGPT アプリ付属の Codex CLI と、設定管理の責務分担は
[`docs/nix/codex-cli.md`](../docs/nix/codex-cli.md) を参照する。
