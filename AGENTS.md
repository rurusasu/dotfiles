# dotfiles repository: 実装時の作業基準

## 最初に決めること

1. 変更対象が `nix/`, `chezmoi/`, `windows/`, `scripts/`, `docker/` のどれかを特定する。
2. パッケージ追加か設定変更かを切り分ける。
3. 反映先が WSL/NixOS か Windows かを決める。

## 変更先の原則

- NixOS/WSL パッケージ: `nix/core/cli.nix`
- Windows パッケージ: `windows/winget/packages.json`
- Windows npm globals: `windows/npm/packages.json`
- ユーザー設定: `chezmoi/` 以下
- Windows 実行ロジック: `scripts/powershell/`

## 実行コマンド

```bash
# WSL/NixOS
nrs
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
nix fmt
```

```powershell
# Windows
pwsh -File scripts/powershell/install.ps1
task test:powershell
task lint:all
```

## コミット前ルール

- Windows から直接 `git commit` しない。
- `task commit -- "message"` を使う。
- 必要に応じて `pre-commit run --all-files` を実行する。

## 参照先

- `docs/architecture.md`
- `docs/chezmoi/`
- `docs/taskfile/lint.md`
- `docs/git/commit.md`
