# PowerShell Scripts

Purpose: Windows セットアップ用 PowerShell スクリプト群

## ディレクトリ構造

```
powershell/
├── AGENTS.md                    # このファイル
├── apply-chezmoi.ps1            # chezmoi 適用スクリプト（スタンドアロン）
├── export-settings.ps1          # Windows 設定エクスポート
├── format-ps1.ps1               # PowerShell スクリプトフォーマッター
├── update-windows-settings.ps1  # winget パッケージ適用
├── update-wslconfig.ps1         # .wslconfig 適用
├── handlers/                    # セットアップハンドラー
├── lib/                         # 共通ライブラリ
└── tests/                       # Pester テスト
```

## アーキテクチャ

### ハンドラーパターン

セットアップ処理は `SetupHandlerBase` を継承したハンドラークラスで実装：

```powershell
class MyHandler : SetupHandlerBase {
    MyHandler() {
        $this.Name = "MyHandler"
        $this.Description = "説明"
        $this.Order = 50  # 実行順序
    }
    
    [bool] CanApply([SetupContext]$ctx) {
        # 適用可能かチェック
        return $true
    }
    
    [SetupResult] Apply([SetupContext]$ctx) {
        # 処理を実行
        return $this.CreateSuccessResult("完了")
    }
}
```

### 実行順序

| Order | ハンドラー | 説明 |
|-------|-----------|------|
| 10 | WslConfig | .wslconfig 適用 + VHD 拡張 |
| 20 | Docker | Docker Desktop WSL 連携 |
| 30 | VscodeServer | VS Code Server キャッシュ/事前インストール |
| 100 | Chezmoi | chezmoi dotfiles 適用 |

## テスト

```powershell
# テスト実行
cd scripts/powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-Tests.ps1
```

- カバレッジ目標: 80%（現在 99.13%）
- フレームワーク: Pester 5.x

## 外部コマンドのラッパー

`lib/Invoke-ExternalCommand.ps1` で外部コマンドをラップし、テストでモック可能にしています：

- `Invoke-Wsl` - WSL コマンド
- `Invoke-Chezmoi` - chezmoi コマンド
- `Invoke-Diskpart` - diskpart コマンド
- その他ファイル/プロセス操作ラッパー
