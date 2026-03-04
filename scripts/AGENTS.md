# scripts: 実装対象と実行経路

## 役割

- `scripts/sh/`: Linux/WSL 向けシェルスクリプト
- `scripts/powershell/`: Windows セットアップとハンドラー実装

## 主要エントリーポイント

- Windows 全体セットアップ: `scripts/powershell/install.ps1`
- ユーザー権限ハンドラー: `scripts/powershell/install.user.ps1`
- 管理者権限ハンドラー: `scripts/powershell/install.admin.ps1`
- NixOS WSL postinstall: `scripts/sh/nixos-wsl-postinstall.sh`

## 変更時の判断基準

- Windows 側ロジックを変える場合は `scripts/powershell/` を編集する。
- ラッパー関数が必要な外部コマンド呼び出しは `scripts/powershell/lib/` に追加する。
- テストは `scripts/powershell/tests/` で追加・更新する。

## 実行コマンド

```powershell
pwsh -File scripts/powershell/install.ps1
task test:powershell
```
