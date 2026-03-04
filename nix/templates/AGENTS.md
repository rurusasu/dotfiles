# nix/templates: 開発環境テンプレート

## 管理対象

- `python/` などの `nix flake init --template` 用テンプレート

## 利用コマンド

```bash
nix flake init --template github:YOUR_USER/dotfiles#python
direnv allow
```

## ルール

- テンプレートは再現可能な最小開発環境に限定する。
