# chezmoi: ユーザー設定の編集基準

## 役割

- `chezmoi/` はユーザー dotfiles の source of truth。
- インストールは Nix/winget、設定配布は chezmoi で分離する。

## 変更先の目安

- `dot_*`: `~/.<name>/` へ直接展開
- `shells/`, `cli/`, `terminals/`, `editors/`, `github/`, `ssh/`, `secret/`: `.chezmoiscripts` 経由で展開

## 変更時の必須確認

1. `.chezmoiignore.tmpl` がターゲット名ベースで正しく除外されること。
2. 1Password / `op` / secret template 方針は `docs/1password/README.md` と OS 別 docs に従うこと。
3. Chezmoi で secret を扱う場合は `docs/1password/README.md` の Chezmoi 方針を確認すること。
4. `.chezmoi.toml.tmpl` を変更したら `chezmoi init` で再生成すること。`[data]` 追加が反映されず `map has no entry for key` で apply が止まる。
5. `AGENTS.md`/`README.md` は deploy 対象にしないこと。
6. `.tmpl` ファイルを deploy スクリプトから参照する場合は `include` でインライン展開すること（ファイルコピーでは未展開のまま配置される）。
7. SSH config の `IdentityFile` で参照する公開鍵は、deploy スクリプトで必ずデプロイすること。
8. 1Password SSH Agent / signing の OS 別パスは `docs/1password/` を確認すること。

## 実行

```bash
chezmoi apply
```

```powershell
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```
