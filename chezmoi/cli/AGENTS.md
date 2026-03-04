# chezmoi/cli: CLI 設定の編集基準

## 管理対象

- `fd/ignore`
- `ripgrep/config`
- `starship/starship.toml`
- `ghq/config`
- `zoxide/env`

## ルール

- 設定ファイルのみ管理する。
- shell 初期化コードは `chezmoi/shells/` または Nix 側で管理する。

## 反映

```bash
chezmoi apply
```
