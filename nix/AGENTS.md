# nix: 構成変更時の作業基準

## 役割

- NixOS/WSL のシステム構成
- flake-parts による出力定義
- OS 構成へ統合するアプリと Home Manager 設定

## 編集先の目安

- システム設定: `nix/defaults.nix:systemDefaults`。末尾の構成登録で `specialArgs.platform` と CPU の `system` を選択する
- 再利用モジュール: `nix/modules/`
- 共通 OS / Home Manager 設定: `nix/defaults.nix:systemDefaults`。共通・OS 別ユーザー設定も同じ `home-manager.sharedModules` にまとめる。アプリ固有の設定・サービス・activation は `nix/modules/`
- Unix のパッケージ導入・アプリ設定: `nix/modules/`。アプリごとの module が `programs.*.enable` / `home.packages`、package 選択、設定・連携、専用の実行依存を管理する
- Homebrew / nix-homebrew・cask・ユーザー PATH は `nix/defaults.nix` にまとめる
- enable・単純な package list・単一代入だけなら `nix/defaults.nix` の必要な構成へ直接書く。設定・package override・生成・連携を持つアプリは module にまとめ、Neovim の LSP・整形ツール・toolchain は Neovim が所有する
- 共通・OS 別の構成: `discover-modules.nix` が `modules/` 配下のすべての実 module の `default.nix` を自動検出する。通常は Home Manager、`nixos/` / `darwin/` / `system/` ディレクトリ配下は NixOS / nix-darwin / 両 OS 共通の scope とし、対応する評価へ読み込む。アプリごとの import パス登録・公開一覧は作らない。`nix/defaults.nix:systemDefaults` の型付き option で有効化し、設定・package・service・activation は enable に従わせる。純粋な factory・renderer は通常の関数として利用し、自動検出の入口名を付けない
- Windows の導入情報: `windows/{winget,npm,pnpm}/packages.json` を直接管理し、Unix module から生成しない
- 共通キー配列: `nix/home/keybindings/bindings.nix`。AeroSpace / Hyprland / Ghostty / Neovim の生成関数・ユーザー設定は各アプリ module に置く。純粋な関数を Home Manager module の imports に渡さない
- flake wiring: root の `flake.nix`。custom package の出力は `nix/defaults.nix`、テストの自動検出は `nix/tests/discover.nix`、flake との接続は `nix/tests/default.nix`、formatter は `nix/treefmt.nix`
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
