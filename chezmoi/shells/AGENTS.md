# chezmoi/shells: シェル初期化設定

## 管理対象

- `bashrc`（Unix の Home Manager と Windows の chezmoi で使用）
- `zoxide.bash`（Windows の `.bashrc` にのみ追記）
- `fzf.bash`（Windows の `.bashrc` にのみ追記）
- `profile`（Windows 向け）
- `Microsoft.PowerShell_profile.ps1`（Windows 向け）

> **Unix の Bash / zsh 起動ファイルは Home Manager が管理する。**
> NixOS/WSL、macOS via nix-darwin、standalone Linux では `nix/home/common.nix` が
> `.bashrc`、`.bash_profile`、`.profile` を生成し、
> `nix/modules/shells/zsh/default.nix` が zsh の導入・共通設定を管理する。
> Unix の chezmoi adapter はこれらをデプロイしない。
> Bash の alias / widget はここにある `bashrc` を Home Manager が読み込む。
> zoxide の初期化・Alt+Q は Unix では `nix/home/zoxide.nix`、Windows では `zoxide.bash` が担当する。
> fzf の検索条件・Alt+D/T/R は Unix では `nix/home/fzf.nix`、Windows では `fzf.bash` が担当する。

## 変更ルール

1. bash/pwsh の共通機能は挙動を揃える。
2. 秘密情報は直接書かず `~/.config/shell/secret.*` を source する。
3. alias 追加は既存キーと衝突しないことを確認する。
4. zsh の共通 alias・設定は `nix/modules/shells/zsh/default.nix` の
   `programs.zsh` に書く。chezmoi には zsh 固有の設定を追加しない。

## 反映

```bash
chezmoi apply
```
