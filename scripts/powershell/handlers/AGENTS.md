# Handlers

Purpose: セットアップハンドラーの実装

## ファイル一覧

| ファイル                   | Order | 説明                                                              |
| -------------------------- | ----- | ----------------------------------------------------------------- |
| `Handler.Winget.ps1`       | 5     | winget パッケージ管理（import/export、インストール済みスキップ）  |
| `Handler.Codex.ps1`        | 6     | Codex CLI シンボリックリンク作成                                  |
| `Handler.Npm.ps1`          | 6     | npm グローバルパッケージ管理（インストール済みスキップ）          |
| `Handler.Bun.ps1`          | 7     | bun グローバルパッケージ管理                                      |
| `Handler.Chezmoi.ps1`      | 10    | chezmoi dotfiles 適用（1Password CLI 連携、--force で自動上書き） |
| `Handler.NixRebuild.ps1`   | 15    | nixos-rebuild switch、bun グローバル、pre-commit install          |
| `Handler.WslConfig.ps1`    | 20    | .wslconfig 適用                                                   |
| `Handler.VhdManager.ps1`   | 21    | WSL VHD サイズ拡張                                                |
| `Handler.Docker.ps1`       | 30    | Docker Desktop WSL 連携、docker-desktop distro 作成               |
| `Handler.VscodeServer.ps1` | 40    | VS Code Server キャッシュクリア、事前インストール                 |
| `Handler.NixOSWSL.ps1`     | 50    | NixOS-WSL インストール、Post-install（リアルタイムログ）          |
| `Handler.OpenClaw.ps1`     | 120   | OpenClaw Telegram AI ゲートウェイ セットアップ                    |

## ハンドラー実装ルール

1. **`SetupHandlerBase` を継承**

   ```powershell
   class MyHandler : SetupHandlerBase { ... }
   ```

2. **コンストラクタで必須プロパティを設定**
   - `Name`: ハンドラー名（スキップリストで使用）
   - `Description`: 説明
   - `Order`: 実行順序（小さいほど先に実行）
   - `RequiresAdmin`: 管理者権限が必要か

3. **`CanApply()` で適用可能かチェック**
   - `$true`: 適用を実行
   - `$false`: スキップ

4. **`Apply()` で処理を実行**
   - 成功: `$this.CreateSuccessResult("メッセージ")`
   - 失敗: `$this.CreateFailureResult("メッセージ", $exception)`

5. **外部コマンドはラッパー関数経由**
   - `Invoke-Wsl`, `Invoke-Chezmoi` 等を使用
   - 直接 `& wsl` を呼ばない（モック不可）

## 新しいハンドラーの追加

1. `Handler.<Name>.ps1` を作成
2. `SetupHandlerBase` を継承したクラスを実装
3. `tests/handlers/Handler.<Name>.Tests.ps1` でテストを作成
4. Order を適切に設定（依存関係を考慮）
