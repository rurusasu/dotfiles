# nix: 構成変更時の作業基準

## 役割

- NixOS/WSL のシステム構成
- flake-parts による出力定義
- OS 構成へ統合するアプリと Home Manager 設定

## 編集先の目安

- ホスト固有: `nix/hosts/`
- 再利用モジュール: `nix/modules/`
- Home Manager: `nix/home/`
- パッケージ SSOT: `nix/packages/catalog/`（カテゴリ別に単一定義）
- provider 選択・検証: `nix/packages/providers/`、installer metadata: `nix/packages/install/`
- パッケージの公開入口: `nix/packages/sets.nix`（既存 API を保つ合成だけ）
- 共通キー配列・設定生成関数・ユーザー設定: `nix/home/keybindings/`。host 配下には OS の service/有効化・競合解除を置く。純粋な関数を Home Manager module の imports に渡さない
- flake wiring: root の `flake.nix`。package 出力は `nix/packages/outputs.nix`、テスト登録は `nix/tests/default.nix`、formatter は `nix/formatter.nix`
- nix-unit の値テスト: `nix/tests/unit/`
- ビルド・実行テストの derivation: `nix/tests/build/`
- テスト用の共有入力: `nix/tests/fixtures/`

テストの登録は `nix/tests/default.nix`、配置・実行方法は [tests/README.md](tests/README.md) を参照する。
flake の `checks` は nix-unit とビルドテストの公開入口であり、ディレクトリの分類名ではない。

データ、provider 選択、配布 metadata、host 動作は変更理由が異なるため分離する。
SSOT を巨大な 1 ファイルと解釈しない。詳細は [分割の理由と編集先](../docs/nix/package-management.md#分割の理由と編集先)。
キー配列も同じ境界で分割する。native NixOS と WSL を同じデスクトップとして扱わない。詳細は [対応範囲](../docs/chezmoi/omarchy.md)。

## 実行

```bash
./install.sh
```
