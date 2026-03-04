# nix/packages: `nix profile` 向け package set

## 管理対象

- `default.nix`: package set 定義
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
