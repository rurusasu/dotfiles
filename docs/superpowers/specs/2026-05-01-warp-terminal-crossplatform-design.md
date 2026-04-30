# Warp Terminal クロスプラットフォームインストール設計

## 概要

Warp Terminal を Windows（winget）と Linux/WSL（Nix home-manager）の両方でインストール・設定管理できるようにする。既存の wezterm と同じパターンを踏襲する。

## アーキテクチャ

### パッケージ管理

`nix/packages/sets.nix` の catalog に `warp-terminal` エントリを追加する。

```nix
warp-terminal = {
  pkg = pkgs.warp-terminal;
  winget = "Warp.Warp";
  category = "terminal";
};
```

- **Nix（Linux/WSL）**: `pkgs.warp-terminal` が home-manager 経由でインストールされる
- **Windows**: `winget.nix` が `Warp.Warp` を `packages.json` に自動生成し、`task install` で反映される

### 設定管理

`chezmoi/terminals/warp/keybindings.yaml` を scaffold として新規作成する（コメントのみ）。フォーマットは `action_name: key-binding` マップ形式（例: `editor_view:add_cursor_below: cmd-shift-a`）。空の scaffold はコメント行のみとし、Warp にカスタムキーバインドなしとして扱わせる。

デプロイ先：

| OS        | デプロイ先                                         |
| --------- | -------------------------------------------------- |
| Linux/WSL | `~/.warp/keybindings.yaml`                         |
| Windows   | `%LOCALAPPDATA%\warp\Warp\config\keybindings.yaml` |

### デプロイスクリプト変更

`chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl`（Windows）と `run_onchange_deploy.sh.tmpl`（Linux）を更新する：

1. ハッシュ行に `terminals/warp/keybindings.yaml` を追加（ファイル変更時に自動再デプロイ）
2. `Deploy-File` / `deploy_file` 呼び出しを追加

## 変更ファイル一覧

| ファイル                                                                | 変更種別                           |
| ----------------------------------------------------------------------- | ---------------------------------- |
| `nix/packages/sets.nix`                                                 | 編集（warp-terminal エントリ追加） |
| `chezmoi/terminals/warp/keybindings.yaml`                               | 新規作成（scaffold）               |
| `chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl` | 編集（Warp デプロイ追加）          |
| `chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.sh.tmpl`  | 編集（Warp デプロイ追加）          |

## スコープ外

- Warp の themes ディレクトリ管理（必要になった時点で追加）
- Windows の `packages.json` 直接編集（`sets.nix` から自動生成）
- macOS 対応（現リポジトリは未対応）
