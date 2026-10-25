# nix: 構成変更時の作業基準

## 役割

- NixOS/WSL のシステム構成
- flake-parts による出力定義
- OS 構成へ統合するアプリと Home Manager 設定

## 編集先の目安

- システム設定: `nix/hosts/{darwin,nixos,linux,wsl}.nix`。OS・CPU 別のサブディレクトリは作らず、CPU は `system` 引数で選択する
- 再利用モジュール: `nix/modules/`
- Home Manager: 共通設定は `nix/home/common.nix`、Darwin / WSL は `nix/home/{darwin,wsl}.nix`、native / standalone Linux は `nix/hosts/default.nix` の `linuxHome`
- Unix のパッケージ導入・アプリ設定: `nix/modules/`。CLI・GUI の導入宣言は `tools.nix`、各アプリ固有の設定・連携・package 定義は各 module にまとめる
- CLI・GUI の `programs.*.enable` と `home.packages`: `nix/modules/tools.nix`。各アプリ module は設定・連携・package override を担当する
- ホストのパッケージ構成: GUI は `tools.linuxDesktop` / `tools.wslDesktop` / `tools.darwin` を import して選択する。共有 CLI は `nix/home/common.nix` が `tools.homeManager` を選択する
- Windows の導入情報: `windows/{winget,npm,pnpm}/packages.json` を直接管理し、Unix module から生成しない
- 共通キー配列・設定生成関数・ユーザー設定: `nix/home/keybindings/`。Darwin の AeroSpace とユーザー shortcut は `darwin.nix`、native NixOS の OS service・セッション有効化は `nix/hosts/linux.nix` に置く。純粋な関数を Home Manager module の imports に渡さない
- flake wiring: root の `flake.nix`。custom package の出力は `nix/outputs.nix`、テスト登録は `nix/tests/default.nix`、formatter は `nix/formatter.nix`
- nix-unit の値テスト: `nix/tests/unit/`
- ビルド・実行テストの derivation: `nix/tests/build/`
- テスト用の共有入力: `nix/tests/fixtures/`

テストの登録は `nix/tests/default.nix`、配置・実行方法は [tests/README.md](tests/README.md) を参照する。
flake の `checks` は nix-unit とビルドテストの公開入口であり、ディレクトリの分類名ではない。

Unix の CLI・GUI 導入は `tools.nix`、各アプリ固有の設定・連携・package 定義は各 module、Windows の導入情報は独立した manifest、OS の動作と `tools.nix` の選択子の import は host に分ける。詳細は [分割の理由と編集先](../docs/nix/package-management.md#分割の理由と編集先)。
キー配列も同じ境界で分割する。native NixOS と WSL を同じデスクトップとして扱わない。詳細は [対応範囲](../docs/chezmoi/omarchy.md)。

## 実行

```bash
./install.sh
```
