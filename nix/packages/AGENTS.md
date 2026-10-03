# nix/packages: パッケージ SSOT + 補助定義

## 管理対象

- `catalog/*.nix`: カテゴリ別 package と provider metadata の SSOT。各 package を一度だけ定義する
- `catalog/default.nix`, `catalog/merge.nix`: カテゴリの合成、重複定義の検出
- `catalog/context.nix`: 共通の package 構築用依存値
- `providers/`: provider の共通処理、正規化、選択、coverage 検証
- `install/`: Node 配布、Windows installer/検証/専用アプリの metadata
- `sets.nix`: 各責務を合成し、既存 consumer 向けの export API を維持する入口
- `winget.nix`: winget/npm/pnpm JSON 生成 derivation
- 必要に応じて `<package>/default.nix`: custom package build

## 利用コマンド

```bash
./install.sh
nix build .#package-support-report
```

## ルール

- パッケージと provider metadata の定義が責務。適用は OS 構成と Home Manager に統合し、独立した `nix profile` 用の集合出力は公開しない。dotfiles 設定は扱わない。
- データ、選択ロジック、配布契約、host 動作は変更理由が異なるため分離する。SSOT は単一定義を意味し、単一ファイルを意味しない。
- package 追加は既存の `catalog/<category>.nix`、配布方式の変更は `install/`、選択ルールの変更は `providers/` を編集する。custom derivation の既存パスは保つ。
- 分割方針と consumer の対応は [パッケージ管理](../../docs/nix/package-management.md#分割の理由と編集先) を参照する。
