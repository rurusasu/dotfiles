# nix: 構成変更時の作業基準

## 役割

- NixOS/WSL のシステム構成
- flake-parts による出力定義
- OS 構成へ統合するアプリと Home Manager 設定

## 編集先の目安

- システム設定: `nix/hosts/default.nix` と各 OS の `nix/hosts/<platform>/default.nix`。構成登録は `nix/defaults.nix`
- 再利用モジュール: `nix/modules/`
- Home Manager のユーザー情報・stateVersion・共通設定は `nix/home/`、OS 基盤設定は `nix/hosts/`。アプリの OS 別設定も `nix/modules/` に置き、OS 別 home ファイルは作らない。
- Unix のパッケージ導入・アプリ設定: `nix/modules/`。アプリごとの module が `programs.*.enable` / `home.packages`、package 選択、設定・連携、専用の実行依存を管理する
- macOS の Steam は公式配布物の Nix package、Google Drive は公式 DMG と PKG の適用を Nix が管理する。Homebrew は使わない。
- Unix のアプリ導入・有効化・設定・OS 差分は各 `nix/modules/` の module が所有する。原則として module 内で標準の `programs.<name>.enable = true` を宣言する。module のないアプリを home の package list で追加しない。
- 共通アプリ module は `nix/modules/default.nix` の `imports` に明示する。アプリ内の子 module は親の `imports`、OS 固有の module は各 hosts から読み込む。有効化は型付き option で選び、package・設定・service・activation を enable に従わせる。
- Windows の導入情報: `chezmoi/winget/packages.json` を直接管理し、Unix module から生成しない
- 共通キー配列: `nix/home/keybindings/bindings.nix`。AeroSpace / Hyprland / Ghostty / Neovim の生成関数・ユーザー設定は各アプリ module に置く。純粋な関数を Home Manager module の imports に渡さない
- flake wiring: root の `flake.nix`。custom package の出力は `nix/defaults.nix`、テストの自動検出は `nix/tests/discover.nix`、flake との接続は `nix/tests/default.nix`、formatter は `nix/modules/formatters/default.nix`
- nix-unit の値テスト: `nix/tests/unit/`。統合設定は `defaults/`、アプリは本番と同じ `modules/` の分類に置く
- ビルド・実行テスト: `nix/tests/build/**/*.check.nix` に check 名をキーとする derivation の属性セットを返す。本番に対応する `modules/` / `defaults/` / `treefmt/` に分ける
- テスト用の共有入力: `nix/tests/fixtures/`

テストは `unit/**/*.nix` / `build/**/*.check.nix` から自動検出し、個別の登録パス一覧は作らない。共有 context の `fixtures.mkHome` / `fixtures.mkHomeWith`、Darwin OS module は `fixtures.mkDarwin` を使う。テスト定義は必要な context 引数だけを受け取り、fixture・helper・asset も `fixtures` / `homeConfigurations` / `code` / `files` で参照する。ローカルパス・import・個別の資源 catalog は書かない。配置・実行方法は [tests/README.md](tests/README.md) を参照する。
flake の `checks` は nix-unit とビルドテストの公開入口であり、ディレクトリの分類名ではない。

Unix の CLI・GUI はアプリごとの module が導入・設定・連携を所有し、共通・OS 別構成は module の外で組み立てる。Windows の導入情報は独立した manifest が所有する。ディレクトリ名はこのリポジトリの配置方針であり、公式の必須構成ではない。詳細は [分割の理由と編集先](../docs/nix/package-management.md#分割の理由と編集先)。
キー配列も同じ境界で分割する。native NixOS と WSL を同じデスクトップとして扱わない。詳細は [対応範囲](../docs/chezmoi/omarchy.md)。

## 実行

```bash
./install.sh
```
