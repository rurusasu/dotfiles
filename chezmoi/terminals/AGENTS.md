# chezmoi/terminals: ターミナル設定の統一方針

## 管理対象

- `wezterm/wezterm.lua`
- `windows-terminal/settings.json`
- `warp/keybindings.yaml`
- `warp/settings.toml`

## ルール

- ペイン/タブ操作キーは両ターミナルで極力統一する。
- OS 固有設定は各ターミナル配下で分離する。

## 反映

```bash
chezmoi apply
```
