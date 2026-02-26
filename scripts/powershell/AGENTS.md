# PowerShell Scripts - AI Agent Instructions

このドキュメントは AI エージェントが PowerShell スクリプトを開発・保守する際のガイドラインです。

## 📖 ドキュメント構成

詳細なドキュメントは [docs/scripts/powershell/](../../docs/scripts/powershell/) ディレクトリに配置されています:

- **[アーキテクチャ](../../docs/architecture.md)** - 全体アーキテクチャとハンドラーシステムの設計
- **[テスト](../../docs/scripts/powershell/testing.md)** - Pester v5 の使用方法とテストパターン
- **[ハンドラー開発ガイド](../../docs/scripts/powershell/handler-development.md)** - 新しいハンドラーの作成手順
- **[コーディング規約](../../docs/scripts/powershell/coding-standards.md)** - 命名規則、スタイル、ベストプラクティス
- **[重要な原則](../../docs/scripts/powershell/principles.md)** - 冪等性、テスタビリティ、エラーリカバリー

## ⚠️ ガードレール（必ず守ること）

これらの原則は**絶対に守る必要があります**。違反すると、システムが正しく動作しません。

### 1. ハンドラーの命名規則

```powershell
# ✅ 正しい
# ファイル名: handlers/Handler.Docker.ps1
class DockerHandler : SetupHandlerBase { }

# ❌ 誤り（動的ロードされない）
# ファイル名: handlers/docker-handler.ps1
class Docker : SetupHandlerBase { }
```

**ルール**:

- ファイル名: `Handler.{Name}.ps1` パターン
- クラス名: `{Name}Handler` パターン
- 基底クラス: `SetupHandlerBase` を継承

### 2. 外部コマンドのラッパー使用

```powershell
# ✅ 正しい（テスト可能）
$output = Invoke-Wsl -ArgumentList "--list", "--verbose"

# ❌ 誤り（テスト不可）
$output = wsl.exe --list --verbose
```

**ルール**:

- すべての外部コマンドは `Invoke-*` ラッパー経由で実行
- 新しいコマンドは [lib/Invoke-ExternalCommand.ps1](lib/Invoke-ExternalCommand.ps1) にラッパーを追加

### 3. Apply() メソッドの返り値

```powershell
# ✅ 正しい（常に SetupResult を返す）
[SetupResult] Apply([SetupContext]$context) {
    try {
        # 処理
        return $this.CreateSuccessResult("成功")
    } catch {
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}

# ❌ 誤り（例外をスロー）
[SetupResult] Apply([SetupContext]$context) {
    # 処理
    throw "Error occurred"
}
```

**ルール**:

- Apply() は例外をスローせず、常に `SetupResult` を返す
- エラー時は `CreateFailureResult()` を使用

### 4. Pester v5 の使用

```powershell
# ✅ 正しい（Invoke-Tests.ps1 を使用）
cd tests
.\Invoke-Tests.ps1

# ❌ 誤り（直接 Invoke-Pester は v3 を使う可能性）
Invoke-Pester
```

**ルール**:

- テストは必ず [tests/Invoke-Tests.ps1](tests/Invoke-Tests.ps1) 経由で実行
- Pester v5 が自動的にインストール・使用される
- `UseBreakpoints = $false` でモックを有効化
- pre-commit フックでも自動実行される（[.pre-commit-config.yaml](../../.pre-commit-config.yaml)）

### 5. Pester テスト命名規則

```powershell
# ✅ 正しい（"should ..." で始まる、-ForEach でパラメタライズ）
It 'should set <property> to <expected>' -ForEach @(
    @{ property = "Name"; expected = "Docker" }
    @{ property = "Order"; expected = 20 }
) {
    $handler.$property | Should -Be $expected
}

It 'should return true when path exists' {
    # ...
}

# ❌ 誤り（日本語、パラメタライズなし）
It 'Name が Docker に設定される' {
    $handler.Name | Should -Be "Docker"
}

It 'Order が 20 に設定される' {
    $handler.Order | Should -Be 20
}
```

**ルール**:

- `It` ブロック名は `'should ...'` で始める（英語、小文字）
- 類似テストは `-ForEach` でパラメタライズする
- `<property>` 形式のトークンで動的な名前を生成

### 6. 配列操作の安全性

```powershell
# ✅ 正しい（@() でラップ）
$handlers = @()
$handlers = @($handlers | Sort-Object Order)
$count = @($handlers).Count

# ❌ 誤り（Count が undefined になる可能性）
$handlers = $handlers | Sort-Object Order
$count = $handlers.Count
```

**ルール**:

- 配列操作後に Count や他のプロパティにアクセスする場合は `@()` でラップ

## 🔄 ドキュメント更新ポリシー

### いつ更新するか

以下の場合は、該当する [docs/scripts/powershell/](../../docs/scripts/powershell/) のドキュメントを**必ず更新**してください:

1. **実装とドキュメントに差異が出た場合**
   - ハンドラーの Order が変更された
   - 新しいラッパー関数が追加された
   - テストパターンが変更された

2. **新しいガードレールが必要になった場合**
   - バグの原因となる実装パターンが見つかった
   - セキュリティ上の問題が発見された
   - パフォーマンス上の問題が発見された

3. **アーキテクチャが変更された場合**
   - 基底クラスのインターフェースが変更された
   - 実行フローが変更された
   - SharedData の使い方が変更された

### 更新手順

1. 該当するドキュメントファイルを特定する
2. ドキュメントを更新する
3. 必要に応じてこのファイル（AGENTS.md）のガードレールセクションも更新する
4. 変更内容をコミットメッセージに記載する

**例**:

```
docs: Update handler development guide for new Order convention

- Changed Order increment from 10 to 5
- Added example for SharedData validation
- Updated handler-development.md and architecture.md
```

## 🚀 クイックスタート

### 既存コードの理解

1. [アーキテクチャ](../../docs/architecture.md) を読む
2. 既存ハンドラー（例: [Handler.Chezmoi.ps1](handlers/Handler.Chezmoi.ps1)）を確認
3. テスト（例: [Handler.Chezmoi.Tests.ps1](tests/handlers/Handler.Chezmoi.Tests.ps1)）を確認

### 新しいハンドラーの追加

1. [ハンドラー開発ガイド](../../docs/scripts/powershell/handler-development.md) を読む
2. テンプレートをコピーして `handlers/Handler.YourName.ps1` を作成
3. テストファイル `tests/handlers/Handler.YourName.Tests.ps1` を作成
4. テスト実行: `cd tests && .\Invoke-Tests.ps1 -MinimumCoverage 0`
5. 全テスト実行: `.\Invoke-Tests.ps1`

### テストの実行

```powershell
# Taskfile 経由（推奨、commit 時に自動実行）
task test:powershell  # PSScriptAnalyzer lint + Pester tests + bats tests

# 直接実行
cd scripts/powershell/tests

# 全テスト実行（全ディレクトリ + bats）
.\Invoke-Tests.ps1 -All -IncludeBats

# デフォルト（scripts/powershell/tests のみ）
.\Invoke-Tests.ps1

# カバレッジチェックなし（高速）
.\Invoke-Tests.ps1 -MinimumCoverage 0

# 特定のテストファイルのみ
.\Invoke-Tests.ps1 -Path .\handlers\Handler.Chezmoi.Tests.ps1 -MinimumCoverage 0
```

**テスト対象ディレクトリ:**

- `scripts/powershell/tests/` - Pester テスト（ハンドラー、ライブラリ）

**現在の状態**: 240+ テスト、カバレッジ 95%+

### Taskfile による自動テスト

`task commit` で自動実行されます（pre-commit は Nix/Linux 系ツールのみ担当）。

```powershell
# コミット時に自動実行
task commit  # fmt → lint → test:powershell → cz commit

# 手動で PowerShell テストのみ実行
task test:powershell
```

**役割分担:**

| ツール             | 担当                                                                                         |
| ------------------ | -------------------------------------------------------------------------------------------- |
| pre-commit (WSL)   | Nix/Linux系: treefmt, shellcheck, statix, deadnix, markdownlint, typos, gitleaks, actionlint |
| Taskfile (Windows) | PowerShell: lint (PSScriptAnalyzer) + tests (Pester + bats)                                  |

## 📚 プロジェクト概要

**目的**: NixOS-WSL セットアップの自動化とハンドラーシステムの実装

**主要コンポーネント**:

- [install.ps1](../../install.ps1) - メインインストールスクリプト（ハンドラーオーケストレーター、UAC 自動昇格付き）
- [lib/SetupHandler.ps1](lib/SetupHandler.ps1) - ハンドラー基底クラス、共通型定義、オーケストレーション関数
- [lib/Invoke-ExternalCommand.ps1](lib/Invoke-ExternalCommand.ps1) - テスト可能な外部コマンドラッパー
- [lib/Request-AdminElevation.ps1](lib/Request-AdminElevation.ps1) - UAC 自動昇格（管理者権限チェックと再起動）
- `handlers/Handler.*.ps1` - 各機能のセットアップハンドラー（8個）
- `tests/` - Pester v5 テストスイート（240+ テスト、95%+ カバレッジ）
- [PSScriptAnalyzerSettings.psd1](PSScriptAnalyzerSettings.psd1) - PSScriptAnalyzer 静的解析設定
- [treefmt.toml](../../treefmt.toml) - 統一フォーマッター設定（PowerShell含む）

### ディレクトリ構造

```
scripts/powershell/
├── AGENTS.md                    # このファイル（インデックス）
├── PSScriptAnalyzerSettings.psd1 # PSScriptAnalyzer 設定（linting）
├── lib/                         # 共通ライブラリ
│   ├── SetupHandler.ps1         # ハンドラー基底クラス・SetupContext・SetupResult + オーケストレーション関数
│   ├── Invoke-ExternalCommand.ps1 # 外部コマンドラッパー（Mock可能）
│   └── Request-AdminElevation.ps1 # UAC 自動昇格（管理者権限チェック）
├── handlers/                    # セットアップハンドラー
│   ├── Handler.Winget.ps1       # Order 5: winget パッケージ（インストール済みスキップ）
│   ├── Handler.Npm.ps1          # Order 6: npm グローバルパッケージ
│   ├── Handler.Chezmoi.ps1      # Order 10: dotfiles 適用（--force で自動上書き）
│   ├── Handler.WslConfig.ps1    # Order 20: WSL 設定
│   ├── Handler.VhdManager.ps1   # Order 21: VHD サイズ拡張
│   ├── Handler.Docker.ps1       # Order 30: Docker Desktop 連携
│   ├── Handler.VscodeServer.ps1 # Order 40: VS Code Server 管理
│   └── Handler.NixOSWSL.ps1     # Order 50: NixOS-WSL インストール
├── tests/                       # テストファイル
│   ├── Invoke-Tests.ps1         # テストランナー（Pester v5 自動インストール）
│   ├── Install.Tests.ps1        # オーケストレーション関数のテスト
│   ├── PSScriptAnalyzer.Tests.ps1 # PSScriptAnalyzer 静的解析テスト
│   ├── handlers/                # 各ハンドラーのテスト
│   └── lib/                     # ライブラリのテスト

../../install.ps1                # メインエントリーポイント（簡素化済み）
../../treefmt.toml               # 統一フォーマッター設定（PowerShell含む）
../../docs/scripts/powershell/   # 詳細ドキュメント（このファイルから参照）
```

### ハンドラー実行順序

| Order | ハンドラー   | ファイル                 | 説明                                                             |
| ----- | ------------ | ------------------------ | ---------------------------------------------------------------- |
| 5     | Winget       | Handler.Winget.ps1       | winget パッケージ管理（import/export、インストール済みスキップ） |
| 6     | Npm          | Handler.Npm.ps1          | npm グローバルパッケージ管理（インストール済みスキップ）         |
| 10    | Chezmoi      | Handler.Chezmoi.ps1      | chezmoi dotfiles 適用（--force で自動上書き、リアルタイムログ）  |
| 20    | WslConfig    | Handler.WslConfig.ps1    | .wslconfig 適用                                                  |
| 21    | VhdManager   | Handler.VhdManager.ps1   | WSL VHD サイズ拡張                                               |
| 30    | Docker       | Handler.Docker.ps1       | Docker Desktop WSL 連携、docker-desktop distro 作成              |
| 40    | VscodeServer | Handler.VscodeServer.ps1 | VS Code Server キャッシュクリア、事前インストール                |
| 50    | NixOSWSL     | Handler.NixOSWSL.ps1     | NixOS-WSL インストール、Post-install（リアルタイムログ）         |

## 🔗 参考資料

- [Pester Documentation](https://pester.dev/) - Pester v5 公式ドキュメント
- [PowerShell Classes](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes) - PowerShell クラス構文
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) - PowerShell 静的解析ツール
- [treefmt](https://numtide.github.io/treefmt/) - 統一フォーマッター設定ツール

## 💡 ヒント

### トラブルシューティング

問題が発生した場合は、[テスト](../../docs/scripts/powershell/testing.md#トラブルシューティング) のトラブルシューティングセクションを確認してください。

### コードレビューチェックリスト

- [ ] ガードレールをすべて守っているか？
- [ ] 詳細ドキュメントを参照して実装したか？
- [ ] テストが 100% パスするか？
- [ ] カバレッジが 80% 以上か？
- [ ] ドキュメントと実装に差異がないか？
