# chezmoi/editors: エディタ設定の編集基準

## 管理対象

- `vscode/`, `cursor/`, `zed/`, `nvim/`

## 共通ルール

1. フォーマッタ設定は言語ごとに明示する。
2. キーバインド方針は `docs/chezmoi/keybindings.md` に合わせる。
3. VS Code 系 (`vscode`, `cursor`) は設定差分を最小化する。

## 反映

```bash
chezmoi apply
```
