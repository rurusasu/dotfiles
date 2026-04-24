# nix/packages: パッケージ SSOT + 補助定義

## 管理対象

- `sets.nix`: catalog-based SSOT (全パッケージ + winget 対応 + カテゴリ)
- `winget.nix`: winget/pnpm JSON 生成 derivation
- 必要に応じて `<package>/default.nix`: custom package build

## 利用コマンド

```bash
nix profile install .#default
nix profile install .#minimal
nix profile install .#full
nix profile upgrade '.*'
```

## ルール

- パッケージ配布が責務。dotfiles 設定は扱わない。
