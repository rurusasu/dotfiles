# nix/modules/wsl: WSL 共通調整

## 管理対象

- `default.nix`: WSL 互換設定と補助設定

## ルール

- WSL 特有の shim や `NIX_PATH` 調整をここに集約する。
