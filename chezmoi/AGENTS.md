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
3. `onepasswordRead` には 2 引数目で account を明示すること（`.op_account_personal` / `.op_account_work`）。chezmoi 2.70.x で `[onepassword] account` flat 形式は黙って無視される。
4. `.chezmoi.toml.tmpl` を変更したら `chezmoi init` で再生成すること。`[data]` 追加が反映されず `map has no entry for key` で apply が止まる。
5. `AGENTS.md`/`README.md` は deploy 対象にしないこと。
6. `.tmpl` ファイルを deploy スクリプトから参照する場合は `include` でインライン展開すること（ファイルコピーでは未展開のまま配置される）。
7. SSH config の `IdentityFile` で参照する公開鍵は、deploy スクリプトで必ずデプロイすること。
8. `gpg.ssh.program` には 1Password の `op-ssh-sign` を使うこと（`ssh-keygen` は 1Password の鍵にアクセスできない）。

## 実行

```bash
chezmoi apply
```

```powershell
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```
