# windows/winget: パッケージ管理運用

## 編集対象

- `packages.json` は WinGet 標準 import 形式の独立した正本。Nix から生成しない。
- `Sources[].SourceDetails` に source、`Packages[]` に `PackageIdentifier` と必要な標準の `Scope` を記載する。独自のインストール・検証・PATH metadata は追加しない。
- バージョンは指定せず、更新とインストールは WinGet に任せる。コマンドリンク・PATH 登録も WinGet と各アプリの installer が管理する。
- 通常は Windows GUI を管理する。Task・PowerShell・chezmoi はセットアップ用、superfile・eza・fd・ripgrep・lazygit は Windows PowerShell 用、Starship・MinGit は WSL との連携用の明示的な CLI 例外。
- Windows の alias・関数は chezmoi、Unix のアプリと設定は Nix / Home Manager で管理する。
- Windows Dia は手動導入とし、master や独自 MSIX 処理に追加しない。
- `retired-packages.json` は履歴。自動アンインストールには使わない。

## 実行コマンド

`install.cmd` が PowerShell で `winget import` を一度実行する。master 内の `Task.Task` が導入された後、Taskfile の WSL → chezmoi へ進む。Taskfile に別の WinGet 経路を作らない。

```powershell
.\install.cmd
```

## 実装上の注意

- `scripts/powershell/lib/Invoke-ExternalCommand.ps1` は master のパスをそのまま `winget import` に渡す。JSON を独自に解釈しない。
- import の非ゼロ終了は失敗として後続を止める。利用できないパッケージを自動で無視しない。
- 更新・反映と再起動による停止は Taskfile と installer の契約テストで検証する。
