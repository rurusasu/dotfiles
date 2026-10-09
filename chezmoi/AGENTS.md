# chezmoi: ユーザー設定の編集基準

## 役割

- `chezmoi/` は Windows 専用のユーザー dotfiles の source of truth。
- macOS / Linux / WSL のユーザー設定（Codex を含む）は Home Manager が所有する。Unix 向け配布は行わない。
- インストールは Nix/winget、設定配布は chezmoi で分離する。
- デスクトップキー配列は例外として `nix/home/keybindings/` を正本とする。macOS と native NixOS の設定は Nix が所有する。Windows の GlazeWM 設定・補助スクリプトは Nix から生成した成果物を chezmoi が配布し、生成物を直接編集しない。共通 action/key を Windows 用に複製しない。

## 変更先の目安

- `dot_*`: Windows の `~/.<name>/` へ直接展開
- `shells/`, `cli/`, `terminals/`, `github/`, `ssh/`, `secret/`: Windows の `.chezmoiscripts` 経由で展開

## 変更時の必須確認

1. `.chezmoiignore.tmpl` がターゲット名ベースで正しく除外されること。
2. 1Password / `op` / secret template 方針は `docs/1password/README.md` と OS 別 docs に従うこと。
3. Chezmoi で secret を扱う場合は `docs/1password/README.md` の Chezmoi 方針を確認すること。
4. `.chezmoi.toml.tmpl` を変更したら `chezmoi init` で再生成すること。`[data]` 追加が反映されず `map has no entry for key` で apply が止まる。
5. `AGENTS.md`/`README.md` は deploy 対象にしないこと。
6. `.tmpl` ファイルを deploy スクリプトから参照する場合は `include` でインライン展開すること（ファイルコピーでは未展開のまま配置される）。
7. SSH config の `IdentityFile` で参照する公開鍵は、deploy スクリプトで必ずデプロイすること。
8. 1Password SSH Agent / signing の OS 別パスは `docs/1password/` を確認すること。

## データとコメントの境界

- font、theme、release version などの変更される値は `.chezmoidata/` を正本とし、テンプレートやコメントに同じ値を複製しない。
- `# hash: {{ include ... | sha256sum }}` は `run_onchange` の変更検知入力であり、説明用コメントではないため削除しない。
- 値の由来や運用ルールを説明するコメントは残してよいが、現在値を写した version/hash コメントや手動の `script-version` マーカーは追加しない。

## 実行

```bash
chezmoi apply
```

```powershell
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```
