# chezmoi: ユーザー設定の編集基準

## 役割

- `chezmoi/` はユーザー dotfiles の source of truth。
- インストールは Nix/winget、設定配布は chezmoi で分離する。

## 変更先の目安

- `dot_*`: `~/.<name>/` へ直接展開
- `shells/`, `cli/`, `terminals/`, `editors/`, `github/`, `ssh/`, `secret/`: `.chezmoiscripts` 経由で展開

## 変更時の必須確認

1. `.chezmoiignore.tmpl` がターゲット名ベースで正しく除外されること。
2. `onepasswordRead` を使う箇所は `lookPath "op"` でガードすること。
3. `AGENTS.md`/`README.md` は deploy 対象にしないこと。

## 実行

```bash
chezmoi apply
```

```powershell
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```
