# nix: 構成変更時の作業基準

## 役割

- NixOS/WSL のシステム構成
- flake-parts による出力定義
- OS 構成へ統合するアプリと Home Manager 設定

## 編集先の目安

- ホスト固有: `nix/hosts/`
- 再利用モジュール: `nix/modules/`
- Home Manager: `nix/home/`
- Unix のパッケージ導入・アプリ設定: `nix/modules/`。Unix CLI の PATH への導入はすべて `tools.nix`、Linux / WSLg GUI は `desktop.nix`、Darwin system GUI は `desktop-system.nix`、個別アプリの設定・連携は各 module に定義する
- CLI の `programs.*.enable` と `home.packages`: `nix/modules/tools.nix`。各アプリ module は設定・連携・package override を担当する
- ホストのパッケージ構成: 必要な module の imports で選択する
- Windows の導入情報: `windows/{winget,npm,pnpm}/packages.json` を直接管理し、Unix module から生成しない
- 共通キー配列・設定生成関数・ユーザー設定: `nix/home/keybindings/`。host 配下には OS の service/有効化・競合解除を置く。純粋な関数を Home Manager module の imports に渡さない
- flake wiring: root の `flake.nix`。custom package・キー設定の出力は `nix/outputs.nix`、テスト登録は `nix/tests/default.nix`、formatter は `nix/formatter.nix`
- nix-unit の値テスト: `nix/tests/unit/`
- ビルド・実行テストの derivation: `nix/tests/build/`
- テスト用の共有入力: `nix/tests/fixtures/`

テストの登録は `nix/tests/default.nix`、配置・実行方法は [tests/README.md](tests/README.md) を参照する。
flake の `checks` は nix-unit とビルドテストの公開入口であり、ディレクトリの分類名ではない。

Unix CLI の導入は `tools.nix`、設定・連携は機能ごとの module、Windows の導入情報は独立した manifest、OS の動作は host に分ける。詳細は [分割の理由と編集先](../docs/nix/package-management.md#分割の理由と編集先)。
キー配列も同じ境界で分割する。native NixOS と WSL を同じデスクトップとして扱わない。詳細は [対応範囲](../docs/chezmoi/omarchy.md)。

## 実行

```bash
./install.sh
```
