# Handlers

Purpose: セットアップハンドラーの実装

## ファイル一覧

| ファイル | Order | 説明 |
|----------|-------|------|
| `Handler.WslConfig.ps1` | 10 | .wslconfig 適用と VHD 拡張 |
| `Handler.Docker.ps1` | 20 | Docker Desktop WSL 連携設定 |
| `Handler.VscodeServer.ps1` | 30 | VS Code Server キャッシュ削除/事前インストール |
| `Handler.Chezmoi.ps1` | 100 | chezmoi dotfiles 適用 |

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
